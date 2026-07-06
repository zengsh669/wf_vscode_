-- ============================================================
-- usp_Load_RPA_Consolidated.sql
-- Loads SILVER.dbo.RPA_Consolidated from BRONZE source tables.
-- Replaces the ad-hoc CTE query in RPA_Transform_ConsolidatedTable.sql
-- with a proper Silver SP following the TRUNCATE + INSERT pattern.
--
-- Created:  9/6/2026
-- Author:   Shawn Zeng
-- Schedule: Run after all rpa.Reporting_* BRONZE loads complete
--
-- Downstream consumers:
--   - GOLD views / Power BI can join this table with:
--       SILVER.dbo.Claim_Detail_Gen_And_Hosp       (on ClaimKey)
--       SILVER.dbo.ClaimDetailsAtService_optimised  (on ClaimKey)
-- ============================================================

USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_RPA_Consolidated
AS
BEGIN
    SET NOCOUNT ON;

    -- ----------------------------------------------------------------
    -- Step 1: Truncate and reload (full refresh pattern).
    -- Prerequisite: run create_table_RPA_Consolidated.sql first.
    -- ----------------------------------------------------------------
    TRUNCATE TABLE SILVER.dbo.RPA_Consolidated;

    -- ----------------------------------------------------------------
    -- Step 3: Build intermediate CTEs and insert.
    -- ----------------------------------------------------------------
    WITH Reason_Clean AS (
        -- Reads rpa.HPC_ClaimsInfo ONCE.
        -- claimType is selected here so Claims_Flag can reference it.
        -- All HPC fields needed downstream are also selected here to
        -- avoid a second JOIN to this table later.
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
        -- IS NOT NULL added explicitly: NULL <> '' evaluates to UNKNOWN,
        -- which would silently drop NULL rows without this guard.
        WHERE execution_id IS NOT NULL
          AND execution_id <> ''
    ),

    Claims_Flag AS (
        -- Tags Remedial Massage records before the cutoff as 'Exclude'.
        SELECT
            *,
            CASE
                WHEN claimType = 'Remedial Massage' AND process_time < '2025-03-11'
                    THEN 'Exclude'
                ELSE 'Include'
            END AS Flag
        FROM Reason_Clean
    ),

    HIPPOLatestStatus AS (
        -- Most recent HIPPO status per claim.
        -- Range predicate on status_date keeps the filter sargable (index seek).
        SELECT
            mg.claim_id,
            cst.description AS Claim_Status_Type,
            ROW_NUMBER() OVER (
                PARTITION BY mg.claim_id
                ORDER BY mg.claim_status_version DESC
            ) AS rn
        FROM [BRONZE].[dbo].[claim_status] mg
        LEFT JOIN [BRONZE].[dbo].[claim_status_type] cst
            ON cst.claim_status_type = mg.claim_status_type
        WHERE mg.status_date >= '2024-01-01'
    ),

    Claim_Lines_RPA AS (
        -- Seven RPA reporting tables unified into one column schema.
        -- Columns absent in a given source are filled with NULL.
        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber                                AS ClaimID,
            CONCAT(claimNumber, '-', Line_Item_Number) AS ClaimKey,
            memberName, lineID, Provider_Number, Provider_Name,
            Description, Net_Price, Postcode, Service_Date, Reject_Page,
            Item_Number, Line_Item_Number, Hippo_Service_Desc, Hippo_Service_Type,
            'Acupuncture' AS Source
        FROM [BRONZE].[dbo].[rpa.Reporting_Acupuncture]

        UNION ALL

        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber, CONCAT(claimNumber, '-', Line_Item_Number),
            MemberName, lineID, Provider_Number, Provider_Name,
            Description, Net_Price,
            NULL AS Postcode,          -- not captured for Chiro
            Service_Date, Reject_Page, Item_Number, Line_Item_Number,
            Hippo_Service_Desc, Hippo_Service_Type, 'Chiropractic'
        FROM [BRONZE].[dbo].[rpa.Reporting_Chiro]

        UNION ALL

        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber, CONCAT(claimNumber, '-', Line_Item_Number),
            MemberName, lineID, Provider_Number,
            NULL AS Provider_Name,     -- not captured for CHM
            Description, Net_Price, Postcode, Service_Date, Reject_Page,
            Item_Number, Line_Item_Number, Hippo_Service_Desc, Hippo_Service_Type,
            'Chinese Herbal Medicine'
        FROM [BRONZE].[dbo].[rpa.Reporting_CHM]

        UNION ALL

        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber, CONCAT(claimNumber, '-', Line_Item_Number),
            MemberName, lineID, Provider_Number,
            NULL AS Provider_Name,     -- not captured for Dental
            Description, Net_Price,
            NULL AS Postcode,          -- not captured for Dental
            Service_Date, Reject_Page, Item_Number, Line_Item_Number,
            Hippo_Service_Desc, Hippo_Service_Type, 'Dental'
        FROM [BRONZE].[dbo].[rpa.Reporting_Dental]

        UNION ALL

        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber, CONCAT(claimNumber, '-', Line_Item_Number),
            MemberName, lineID, Provider_Number,
            NULL AS Provider_Name,     -- not captured for Massage
            Description, Net_Price, Postcode, Service_Date, Reject_Page,
            Item_Number, Line_Item_Number, Hippo_Service_Desc, Hippo_Service_Type,
            'Massage'
        FROM [BRONZE].[dbo].[rpa.Reporting_Massage]

        UNION ALL

        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber, CONCAT(claimNumber, '-', Line_Item_Number),
            MemberName, lineID,
            NULL AS Provider_Number,   -- not captured for Pharmacy
            NULL AS Provider_Name,
            Description, Net_Price,
            NULL AS Postcode,
            NULL AS Service_Date,      -- not captured for Pharmacy
            Reject_Page,
            NULL AS Item_Number,       -- not captured for Pharmacy
            Line_Item_Number, Hippo_Service_Desc, Hippo_Service_Type, 'Pharmacy'
        FROM [BRONZE].[dbo].[rpa.Reporting_Pharmacy]

        UNION ALL

        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber, CONCAT(claimNumber, '-', Line_Item_Number),
            MemberName, lineID, Provider_Number,
            NULL AS Provider_Name,     -- not captured for Physio
            Description, Net_Price,
            NULL AS Postcode,
            Service_Date, Reject_Page, Item_Number, Line_Item_Number,
            Hippo_Service_Desc, Hippo_Service_Type, 'Physiotherapy'
        FROM [BRONZE].[dbo].[rpa.Reporting_Physio]
    ),

    Claim_Lines_HPC AS (
        -- ClaimInfo rows from HPC — claim-level, no line items.
        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            claimNumber        AS ClaimID,
            NULL               AS ClaimKey,
            NULL               AS memberName,
            NULL               AS lineID,
            NULL               AS Provider_Number,
            NULL               AS Provider_Name,
            NULL               AS Description,
            NULL               AS Net_Price,
            NULL               AS Postcode,
            NULL               AS Service_Date,
            NULL               AS Reject_Page,
            NULL               AS Item_Number,
            NULL               AS Line_Item_Number,
            NULL               AS Hippo_Service_Desc,
            NULL               AS Hippo_Service_Type,
            'ClaimInfo'        AS Source,
            memberID           AS Membership_ID_HPC,
            process_remarks    AS Reasons_HPC,
            Reasons_Display,
            Sub_Reason,
            claim_status       AS Status_HPC,
            process_status     AS ProcessStatus_HPC,
            manualReviewerUsername  AS Manual_Reviewer_Username,
            sendToOpenAI       AS Send_To_Open_AI,
            Flag
        FROM Claims_Flag
    ),

    All_Lines AS (
        -- Merge RPA and HPC rows; pre-compute Sydney date once here.
        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            ClaimID, ClaimKey, memberName, lineID,
            Provider_Number, Provider_Name, Description, Net_Price,
            Postcode, Service_Date, Reject_Page, Item_Number, Line_Item_Number,
            Hippo_Service_Desc, Hippo_Service_Type, Source,
            CAST(
                process_time AT TIME ZONE 'UTC'
                             AT TIME ZONE 'AUS Eastern Standard Time'
            AS DATE)       AS process_date_sydney,
            NULL           AS Membership_ID_HPC,
            NULL           AS Reasons_HPC,
            NULL           AS Reasons_Display,
            NULL           AS Sub_Reason,
            NULL           AS Status_HPC,
            NULL           AS ProcessStatus_HPC,
            NULL           AS Manual_Reviewer_Username,
            NULL           AS Send_To_Open_AI,
            NULL           AS Flag
        FROM Claim_Lines_RPA

        UNION ALL

        SELECT
            execution_id, process_time, abbyTransactionID, timestampUsername,
            ClaimID, ClaimKey, memberName, lineID,
            Provider_Number, Provider_Name, Description, Net_Price,
            Postcode, Service_Date, Reject_Page, Item_Number, Line_Item_Number,
            Hippo_Service_Desc, Hippo_Service_Type, Source,
            CAST(
                process_time AT TIME ZONE 'UTC'
                             AT TIME ZONE 'AUS Eastern Standard Time'
            AS DATE)       AS process_date_sydney,
            Membership_ID_HPC, Reasons_HPC, Reasons_Display, Sub_Reason,
            Status_HPC, ProcessStatus_HPC, Manual_Reviewer_Username,
            Send_To_Open_AI, Flag
        FROM Claim_Lines_HPC
    )

    INSERT INTO SILVER.dbo.RPA_Consolidated
    SELECT
        al.execution_id,
        al.process_time,
        al.process_date_sydney,
        DATENAME(MONTH, al.process_date_sydney)
            + ' ' + CAST(YEAR(al.process_date_sydney) AS VARCHAR(4))   AS MonthYear,
        al.abbyTransactionID,
        al.timestampUsername,
        al.ClaimID,
        al.ClaimKey,
        al.memberName,
        al.lineID,
        al.Provider_Number,
        al.Provider_Name,
        al.Description,
        al.Net_Price,
        al.Postcode,
        al.Service_Date,
        al.Reject_Page,
        al.Item_Number,
        al.Line_Item_Number,
        al.Hippo_Service_Desc,
        al.Hippo_Service_Type,
        al.Source,
        -- COALESCE: HPC row already has these populated; RPA rows fall back to hpc2 JOIN
        COALESCE(al.Membership_ID_HPC,  hpc2.memberID)          AS Membership_ID_HPC,
        COALESCE(al.Reasons_HPC,        hpc2.process_remarks)   AS Reasons_HPC,
        al.Reasons_Display,
        al.Sub_Reason,
        COALESCE(al.Status_HPC,         hpc2.claim_status)      AS Status_HPC,
        COALESCE(al.ProcessStatus_HPC,  hpc2.process_status)    AS ProcessStatus_HPC,
        al.Manual_Reviewer_Username,
        al.Send_To_Open_AI,
        al.Flag,
        hippo.Claim_Status_Type                                  AS MaxClaimStatus_HIPPO,
        fee.critical_red_lower_limit                             AS Red_Lower_Limit,
        fee.critical_red_upper_limit                             AS Red_Upper_Limit,
        fee.warning_blue_lower_limit                             AS Blue_Lower_Limit,
        fee.warning_blue_upper_limit                             AS Blue_Upper_Limit
    FROM All_Lines al

    -- Provides memberID/status for RPA line rows that have no ClaimInfo entry
    LEFT JOIN [BRONZE].[dbo].[rpa.HPC_ClaimsInfo] hpc2
        ON al.ClaimID = hpc2.claimNumber

    LEFT JOIN [BRONZE].[dbo].[item_averagefee] fee
        ON  al.Hippo_Service_Type = fee.service_type
        AND TRY_CONVERT(VARCHAR(50), al.Item_Number) = TRY_CONVERT(VARCHAR(50), fee.item_number)

    -- Latest HIPPO status only
    LEFT JOIN (
        SELECT * FROM HIPPOLatestStatus WHERE rn = 1
    ) hippo
        ON al.ClaimID = TRY_CONVERT(VARCHAR(50), hippo.claim_id);

END;
GO
