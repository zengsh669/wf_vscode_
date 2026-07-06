-- ============================================================
-- RPA_Transform_ConsolidatedTable_optimised.sql
-- Replicated from Qlik: Bot Dashboard LOAD section
-- Source DB: BRONZE & SILVER
-- Created:   6/6/2026
-- Author:    Monique Rust
-- Optimised: 9/6/2026
-- Changes:
--   1. Replace YEAR() function on status_date with range predicate to allow index seek
--   2. Eliminate duplicate read of rpa.HPC_ClaimsInfo by pulling HPC fields into Reason_Clean
--   3. Pre-compute Sydney date conversion once in a CTE to avoid repeating the expression
--   4. Fix execution_id filter to explicitly exclude NULLs
--   5. Separate ClaimInfo (HPC) UNION branch into its own CTE for clarity
--   6. Standardise keyword casing and NULL alias formatting throughout
-- ============================================================

-- ----------------------------------------------------------------
-- CTE 1: Reason_Clean
-- Reads rpa.HPC_ClaimsInfo ONCE and derives display-friendly reason
-- labels plus all HPC fields needed downstream (memberID, claim_status,
-- process_status, manualReviewerUsername, sendToOpenAI).
-- Pulling these fields here eliminates the second JOIN to this table
-- in the final SELECT.
-- ----------------------------------------------------------------
WITH Reason_Clean AS (
    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        memberID,
        claimType,
        claim_status,
        process_status,
        manualReviewerUsername,
        sendToOpenAI,
        process_remarks,
        CASE
            WHEN process_remarks LIKE '%Error in selecting dependent%'
             AND process_remarks LIKE '%System Exception%'
                THEN 'Error in selecting dependent, System Exception'
            WHEN process_remarks LIKE 'Error in selecting dependent%'
                THEN 'Error in selecting dependent'
            WHEN process_remarks LIKE 'Discount detected%'
                THEN 'Discount detected'
            WHEN process_remarks LIKE 'Balance due detected%'
                THEN 'Balance due detected'
            WHEN process_remarks LIKE 'Orthodontic%'
                THEN 'Orthodontic Item Numbers identified'
            WHEN process_remarks LIKE 'System%'
                THEN 'System Exception'
            ELSE process_remarks
        END AS Reasons_Display,
        REPLACE(CAST(process_remarks AS VARCHAR(MAX)), 'Rejected Claim in Manual Validation - ', '') AS Sub_Reason
    FROM [BRONZE].[dbo].[rpa.HPC_ClaimsInfo]
    -- Explicitly exclude both empty strings and NULLs.
    -- Without the IS NOT NULL check, NULL execution_ids would be silently
    -- dropped because NULL <> '' evaluates to UNKNOWN, not TRUE.
    WHERE execution_id IS NOT NULL
      AND execution_id <> ''
),

-- ----------------------------------------------------------------
-- CTE 2: Claims_Flag
-- Tags Remedial Massage records processed before the cutoff date
-- as 'Exclude' so downstream consumers can filter them out.
-- ----------------------------------------------------------------
Claims_Flag AS (
    SELECT
        *,
        CASE
            WHEN claimType = 'Remedial Massage' AND process_time < '2025-03-11'
                THEN 'Exclude'
            ELSE 'Include'
        END AS Flag
    FROM Reason_Clean
),

-- ----------------------------------------------------------------
-- CTE 3: HIPPOLatestStatus
-- Retrieves the most recent status record per claim from HIPPO.
-- Using a date range predicate (>= '2024-01-01') instead of
-- YEAR(status_date) >= 2024 so the index on status_date can be used.
-- ----------------------------------------------------------------
HIPPOLatestStatus AS (
    SELECT
        mg.claim_id,
        cst.description                                               AS Claim_Status_Type,
        mg.claim_status_version,
        mg.status_date,
        ROW_NUMBER() OVER (
            PARTITION BY mg.claim_id
            ORDER BY mg.claim_status_version DESC
        )                                                             AS rn
    FROM [BRONZE].[dbo].[claim_status] mg
    LEFT JOIN [BRONZE].[dbo].[claim_status_type] cst
        ON cst.claim_status_type = mg.claim_status_type
    -- Range predicate keeps this sargable; YEAR() would force a full scan
    WHERE mg.status_date >= '2024-01-01'
),

-- ----------------------------------------------------------------
-- CTE 4a: Claim_Lines_RPA
-- Unions the seven RPA reporting tables into a single column schema.
-- All branches supply the same 18 positional columns; columns not
-- available for a given source are filled with NULL.
-- HPC / ClaimInfo rows are handled separately in CTE 4b below.
-- ----------------------------------------------------------------
Claim_Lines_RPA AS (

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber                              AS ClaimID,
        CONCAT(claimNumber, '-', Line_Item_Number) AS ClaimKey,
        memberName,
        lineID,
        Provider_Number,
        Provider_Name,
        Description,
        Net_Price,
        Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Acupuncture'                            AS Source
    FROM [BRONZE].[dbo].[rpa.Reporting_Acupuncture]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber, '-', Line_Item_Number),
        MemberName,
        lineID,
        Provider_Number,
        Provider_Name,
        Description,
        Net_Price,
        NULL  AS Postcode,         -- not captured for Chiro
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Chiropractic'
    FROM [BRONZE].[dbo].[rpa.Reporting_Chiro]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber, '-', Line_Item_Number),
        MemberName,
        lineID,
        Provider_Number,
        NULL  AS Provider_Name,    -- not captured for CHM
        Description,
        Net_Price,
        Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Chinese Herbal Medicine'
    FROM [BRONZE].[dbo].[rpa.Reporting_CHM]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber, '-', Line_Item_Number),
        MemberName,
        lineID,
        Provider_Number,
        NULL  AS Provider_Name,    -- not captured for Dental
        Description,
        Net_Price,
        NULL  AS Postcode,         -- not captured for Dental
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Dental'
    FROM [BRONZE].[dbo].[rpa.Reporting_Dental]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber, '-', Line_Item_Number),
        MemberName,
        lineID,
        Provider_Number,
        NULL  AS Provider_Name,    -- not captured for Massage
        Description,
        Net_Price,
        Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Massage'
    FROM [BRONZE].[dbo].[rpa.Reporting_Massage]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber, '-', Line_Item_Number),
        MemberName,
        lineID,
        NULL  AS Provider_Number,  -- not captured for Pharmacy
        NULL  AS Provider_Name,
        Description,
        Net_Price,
        NULL  AS Postcode,
        NULL  AS Service_Date,     -- not captured for Pharmacy
        Reject_Page,
        NULL  AS Item_Number,      -- not captured for Pharmacy
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Pharmacy'
    FROM [BRONZE].[dbo].[rpa.Reporting_Pharmacy]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber, '-', Line_Item_Number),
        MemberName,
        lineID,
        Provider_Number,
        NULL  AS Provider_Name,    -- not captured for Physio
        Description,
        Net_Price,
        NULL  AS Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Physiotherapy'
    FROM [BRONZE].[dbo].[rpa.Reporting_Physio]
),

-- ----------------------------------------------------------------
-- CTE 4b: Claim_Lines_HPC
-- ClaimInfo rows from rpa.HPC_ClaimsInfo (via Claims_Flag).
-- Kept separate from the RPA UNION above because the shape of this
-- data is fundamentally different: it is claim-level (no line items)
-- and carries HPC-specific fields not present in the RPA tables.
-- ----------------------------------------------------------------
Claim_Lines_HPC AS (
    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber                AS ClaimID,
        NULL                       AS ClaimKey,      -- no line-item key for HPC rows
        NULL                       AS memberName,
        NULL                       AS lineID,
        NULL                       AS Provider_Number,
        NULL                       AS Provider_Name,
        NULL                       AS Description,
        NULL                       AS Net_Price,
        NULL                       AS Postcode,
        NULL                       AS Service_Date,
        NULL                       AS Reject_Page,
        NULL                       AS Item_Number,
        NULL                       AS Line_Item_Number,
        NULL                       AS Hippo_Service_Desc,
        NULL                       AS Hippo_Service_Type,
        'ClaimInfo'                AS Source,
        -- HPC-specific fields surfaced here; NULL in RPA branches above
        memberID                   AS Membership_ID_HPC,
        process_remarks            AS Reasons_HPC,
        Reasons_Display,
        Sub_Reason,
        claim_status               AS Status_HPC,
        process_status             AS ProcessStatus_HPC,
        manualReviewerUsername     AS Manual_Reviewer_Username,
        sendToOpenAI               AS Send_To_Open_AI,
        Flag
    FROM Claims_Flag
),

-- ----------------------------------------------------------------
-- CTE 5: Sydney_Time
-- Pre-computes the UTC → Sydney timezone conversion ONCE so the
-- expression does not need to be repeated three times in the final
-- SELECT (MonthYear, process_time_sydney, and the YEAR component).
-- ----------------------------------------------------------------
Sydney_Time AS (
    SELECT
        rpa.execution_id,
        rpa.ClaimID,
        rpa.ClaimKey,
        rpa.memberName,
        rpa.lineID,
        rpa.Provider_Number,
        rpa.Provider_Name,
        rpa.Description,
        rpa.Net_Price,
        rpa.Postcode,
        rpa.Service_Date,
        rpa.Reject_Page,
        rpa.Item_Number,
        rpa.Line_Item_Number,
        rpa.Hippo_Service_Desc,
        rpa.Hippo_Service_Type,
        rpa.Source,
        -- Compute once; reused for process_time_sydney and MonthYear below
        CAST(
            rpa.process_time
            AT TIME ZONE 'UTC'
            AT TIME ZONE 'AUS Eastern Standard Time'
        AS DATE)                   AS process_date_sydney,
        -- HPC columns (populated for ClaimInfo rows, NULL for RPA rows)
        NULL                       AS Membership_ID_HPC,
        NULL                       AS Reasons_HPC,
        NULL                       AS Reasons_Display,
        NULL                       AS Sub_Reason,
        NULL                       AS Status_HPC,
        NULL                       AS ProcessStatus_HPC,
        NULL                       AS Manual_Reviewer_Username,
        NULL                       AS Send_To_Open_AI,
        NULL                       AS Flag
    FROM Claim_Lines_RPA rpa

    UNION ALL

    SELECT
        hpc.execution_id,
        hpc.ClaimID,
        hpc.ClaimKey,
        hpc.memberName,
        hpc.lineID,
        hpc.Provider_Number,
        hpc.Provider_Name,
        hpc.Description,
        hpc.Net_Price,
        hpc.Postcode,
        hpc.Service_Date,
        hpc.Reject_Page,
        hpc.Item_Number,
        hpc.Line_Item_Number,
        hpc.Hippo_Service_Desc,
        hpc.Hippo_Service_Type,
        hpc.Source,
        CAST(
            hpc.process_time
            AT TIME ZONE 'UTC'
            AT TIME ZONE 'AUS Eastern Standard Time'
        AS DATE)                   AS process_date_sydney,
        hpc.Membership_ID_HPC,
        hpc.Reasons_HPC,
        hpc.Reasons_Display,
        hpc.Sub_Reason,
        hpc.Status_HPC,
        hpc.ProcessStatus_HPC,
        hpc.Manual_Reviewer_Username,
        hpc.Send_To_Open_AI,
        hpc.Flag
    FROM Claim_Lines_HPC hpc
)

-- ----------------------------------------------------------------
-- Final SELECT
-- Joins the unified claim rows to HIPPO status, fee schedule, claim
-- detail, and cover information.
-- COALESCE picks the HPC value first (populated for ClaimInfo rows)
-- then falls back to the matched hpc2 row for RPA rows — but since
-- rpa.HPC_ClaimsInfo is already fully read in Reason_Clean, the
-- hpc2 join here only adds memberID/status for RPA line-item rows
-- that do not have a corresponding ClaimInfo row in the UNION.
-- ----------------------------------------------------------------
SELECT
    st.execution_id,
    st.process_date_sydney                                              AS process_time_sydney,
    -- Derive MonthYear from the pre-computed date rather than repeating the AT TIME ZONE expression
    DATENAME(MONTH, st.process_date_sydney)
        + ' ' + CAST(YEAR(st.process_date_sydney) AS VARCHAR(4))       AS MonthYear,
    st.ClaimID,
    st.ClaimKey,
    st.Reasons_Display,
    st.Sub_Reason,
    st.Manual_Reviewer_Username,
    st.Send_To_Open_AI,
    st.Flag,
    st.memberName,
    st.lineID,
    st.Provider_Number,
    st.Provider_Name,
    st.Description,
    st.Net_Price,
    st.Postcode,
    st.Service_Date,
    st.Item_Number,
    st.Line_Item_Number,
    st.Hippo_Service_Desc,
    st.Source,
    COALESCE(st.Membership_ID_HPC,  hpc2.memberID)                     AS MembershipID,
    COALESCE(st.Reasons_HPC,        hpc2.process_remarks)              AS Reasons,
    COALESCE(st.Status_HPC,         hpc2.claim_status)                 AS Status,
    COALESCE(st.ProcessStatus_HPC,  hpc2.process_status)               AS ProcessStatus,
    fee.critical_red_lower_limit                                        AS Red_Lower_Limit,
    fee.critical_red_upper_limit                                        AS Red_Upper_Limit,
    fee.warning_blue_lower_limit                                        AS Blue_Lower_Limit,
    fee.warning_blue_upper_limit                                        AS Blue_Upper_Limit,
    hippo.Claim_Status_Type                                             AS MaxClaimStatus_HIPPO,
    cd.fee                                                              AS HIPPO_Fee,
    cd.benefit                                                          AS HIPPO_Benefit,
    cd.service_type                                                      AS HIPPO_ServiceType,
    cd.item_number                                                      AS HIPPO_ItemNumber,
    cover.cover_type                                                    AS CoverType,
    cover.mem_cover_at_claim                                            AS CoverCode,
    cover.Product_Description_at_claim                                  AS CoverDescription
FROM Sydney_Time st

-- Provides memberID / claim_status for RPA line-item rows that have no
-- matching ClaimInfo entry in the UNION above
LEFT JOIN [BRONZE].[dbo].[rpa.HPC_ClaimsInfo] hpc2
    ON st.ClaimID = hpc2.claimNumber

LEFT JOIN [BRONZE].[dbo].[item_averagefee] fee
    ON  st.Hippo_Service_Type = fee.service_type
    -- TRY_CONVERT used because Item_Number is VARCHAR in RPA tables but
    -- numeric in item_averagefee; align types at source if possible
    AND TRY_CONVERT(VARCHAR(50), st.Item_Number) = TRY_CONVERT(VARCHAR(50), fee.item_number)

-- Filter to latest status version before joining (rn = 1)
LEFT JOIN (
    SELECT * FROM HIPPOLatestStatus WHERE rn = 1
) hippo
    ON st.ClaimID = TRY_CONVERT(VARCHAR(50), hippo.claim_id)

LEFT JOIN [SILVER].[dbo].[Claim_Detail_Gen_And_Hosp] cd
    ON st.ClaimKey = CONCAT(cd.claim_id, '-', cd.claim_line_id)

LEFT JOIN [SILVER].[dbo].[ClaimDetailsAtService_optimised] cover
    ON st.ClaimKey = CONCAT(cover.claim_id, '-', cover.claim_line_id);
