--RPA_Transform_ConsolidatedTable
-- ============================================================
-- RPA_Transform_ConsolidatedTable Script
-- Replicated from Qlik: Bot Dashboard LOAD section 
-- Source DB: BRONZE & SILVER
-- Created: 6/6/2026
-- Author: Monique Rust
-- ============================================================

With Reason_Clean AS
(SELECT
        *,
CASE WHEN process_remarks LIKE '%Error in selecting dependent%'
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
                THEN 'System Exception' ELSE process_remarks END AS Reasons_Display,
REPLACE(CAST(process_remarks AS VARCHAR(MAX)),'Rejected Claim in Manual Validation - ','') AS Sub_Reason
    FROM [BRONZE].[dbo].[rpa.HPC_ClaimsInfo]
	WHERE execution_id <> ''),

Claims_Flag AS
(SELECT *, CASE WHEN claimType = 'Remedial Massage' AND process_time < '2025-03-11'
                THEN 'Exclude'ELSE 'Include' END AS Flag
	FROM Reason_Clean),

HIPPOLatestStatus AS
(SELECT
        mg.claim_id,
		cst.description as 'Claim_Status_Type',
        mg.claim_status_version,
        mg.status_date,
        ROW_NUMBER() OVER
        (PARTITION BY mg.claim_id
            ORDER BY mg.claim_status_version DESC) AS rn
    FROM [BRONZE].[dbo].[claim_status] mg
	Left join [BRONZE].[dbo].[claim_status_type] cst on cst.claim_status_type = mg.claim_status_type
    WHERE year(mg.status_date) >= '2024'),

Claim_Lines AS
(SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber                               AS ClaimID,
        CONCAT(claimNumber,'-',Line_Item_Number)  AS ClaimKey,
		NULL									  AS Membership_ID_HPC,
		NULL									  AS Reasons_HPC,
		NULL									  AS Reasons_Display,
		NULL									  AS Sub_Reason,
		NULL									  AS Status_HPC,
		NULL									  AS ProcessStatus_HPC,
		NULL									  AS Manual_Reviewer_Username,
		NULL									  AS Send_To_Open_AI,
		NULL										AS Flag,
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
        'Acupuncture'                             AS Source,
        'Acupuncture'                             AS Service_Type
    FROM [BRONZE].[dbo].[rpa.Reporting_Acupuncture]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber,'-',Line_Item_Number),
		NULL									  AS Membership_ID_HPC,
		NULL									  AS Reasons_HPC,
		NULL									  AS Reasons_Display,
		NULL									  AS Sub_Reason,
		NULL									  AS Status_HPC,
		NULL									  AS ProcessStatus_HPC,
		NULL									  AS Manual_Reviewer_Username,
		NULL									  AS Send_To_Open_AI,
		NULL										AS Flag,
        MemberName,
        lineID,
        Provider_Number,
        Provider_Name,
        Description,
        Net_Price,
        NULL									AS Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Chiropractic',
        'Chiropractic'
    FROM [BRONZE].[dbo].[rpa.Reporting_Chiro]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber,'-',Line_Item_Number),
		NULL									  AS Membership_ID_HPC,
		NULL									  AS Reasons_HPC,
		NULL									  AS Reasons_Display,
		NULL									  AS Sub_Reason,
		NULL									  AS Status_HPC,
		NULL									  AS ProcessStatus_HPC,
		NULL									  AS Manual_Reviewer_Username,
		NULL									  AS Send_To_Open_AI,
		NULL										AS Flag,
        MemberName,
        lineID,
        Provider_Number,
        NULL									AS Provider_Name,
        Description,
        Net_Price,
        Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Chinese Herbal Medicine',
        'Chinese Herbal Medicine'
    FROM [BRONZE].[dbo].[rpa.Reporting_CHM]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber,'-',Line_Item_Number),
		NULL									  AS Membership_ID_HPC,
		NULL									  AS Reasons_HPC,
		NULL									  AS Reasons_Display,
		NULL									  AS Sub_Reason,
		NULL									  AS Status_HPC,
		NULL									  AS ProcessStatus_HPC,
		NULL									  AS Manual_Reviewer_Username,
		NULL									  AS Send_To_Open_AI,
		NULL										AS Flag,
        MemberName,
        lineID,
        Provider_Number,
        NULL									AS Provider_Name,
        Description,
        Net_Price,
         NULL									AS Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Dental',
        'Dental'
    FROM [BRONZE].[dbo].[rpa.Reporting_Dental]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber,'-',Line_Item_Number),
		NULL									  AS Membership_ID_HPC,
		NULL									  AS Reasons_HPC,
		NULL									  AS Reasons_Display,
		NULL									  AS Sub_Reason,
		NULL									  AS Status_HPC,
		NULL									  AS ProcessStatus_HPC,
		NULL									  AS Manual_Reviewer_Username,
		NULL									  AS Send_To_Open_AI,
		NULL										AS Flag,
        MemberName,
        lineID,
        Provider_Number,
        NULL									AS Provider_Name,
        Description,
        Net_Price,
        Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Massage',
        'Massage'
    FROM [BRONZE].[dbo].[rpa.Reporting_Massage]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber,'-',Line_Item_Number),
		NULL									  AS Membership_ID_HPC,
		NULL									  AS Reasons_HPC,
		NULL									  AS Reasons_Display,
		NULL									  AS Sub_Reason,
		NULL									  AS Status_HPC,
		NULL									  AS ProcessStatus_HPC,
		NULL									  AS Manual_Reviewer_Username,
		NULL									  AS Send_To_Open_AI,
		NULL										AS Flag,
        MemberName,
        lineID,
        NULL									AS Provider_Number,
        NULL									AS Provider_Name,
        Description,
        Net_Price,
         NULL									AS Postcode,
        NULL,
        Reject_Page,
        NULL,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Pharmacy',
        'Pharmacy'
    FROM [BRONZE].[dbo].[rpa.Reporting_Pharmacy]

    UNION ALL

    SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        CONCAT(claimNumber,'-',Line_Item_Number),
		NULL									  AS Membership_ID_HPC,
		NULL									  AS Reasons_HPC,
		NULL									  AS Reasons_Display,
		NULL									  AS Sub_Reason,
		NULL									  AS Status_HPC,
		NULL									  AS ProcessStatus_HPC,
		NULL									  AS Manual_Reviewer_Username,
		NULL									  AS Send_To_Open_AI,
		NULL									  AS Flag,
        MemberName,
        lineID,
        Provider_Number,
        NULL									AS Provider_Name,
        Description,
        Net_Price,
         NULL									AS Postcode,
        Service_Date,
        Reject_Page,
        Item_Number,
        Line_Item_Number,
        Hippo_Service_Desc,
        Hippo_Service_Type,
        'Physiotherapy',
        'Physiotherapy'
    FROM [BRONZE].[dbo].[rpa.Reporting_Physio]
	
	UNION ALL

	SELECT
        execution_id,
        process_time,
        abbyTransactionID,
        timestampUsername,
        claimNumber,
        NULL										as ClaimKey,
		memberID									as Membership_ID_HPC,
		process_remarks							    as Reasons_HPC,
		Reasons_Display,
		Sub_Reason,
		claim_status								as Status_HPC,
		process_status								as ProcessStatus_HPC,
		manualReviewerUsername						as Manual_Reviewer_Username,
		sendToOpenAI								as Send_To_Open_AI,
		Flag										as Flag,
        NULL										as MemberName,
        NULL										as lineID,
        NULL										as Provider_Number,
        NULL										as Provider_Name,
        NULL										as Description,
        NULL										as Net_Price,
        NULL										as Postcode,
        NULL										as Service_Date,
        NULL										as Reject_Page,
        NULL										as Item_Number,
        NULL										as Line_Item_Number,
        NULL										as Hippo_Service_Desc,
        NULL										as Hippo_Service_Type,
        'ClaimInfo',
        'ClaimInfo'
    FROM Claims_Flag)

SELECT
    rpacl.execution_id,
	CAST(rpacl.process_time AT TIME ZONE 'UTC'
                 AT TIME ZONE 'AUS Eastern Standard Time' AS DATE) AS process_time_sydney,
DATENAME(MONTH, CAST(rpacl.process_time AT TIME ZONE 'UTC'
AT TIME ZONE 'AUS Eastern Standard Time' AS DATE)) + ' '+ CAST(YEAR(CAST(rpacl.process_time AT TIME ZONE 'UTC'
AT TIME ZONE 'AUS Eastern Standard Time' AS DATE)) AS VARCHAR(4)) AS MonthYear,
	rpacl.ClaimID, 
	rpacl.ClaimKey,
	rpacl.Reasons_Display,
	rpacl.Sub_Reason,
	rpacl.Manual_Reviewer_Username,
	rpacl.Send_To_Open_AI,
	rpacl.Flag,
	rpacl.memberName,
	rpacl.lineID,
	rpacl.Provider_Number,
	rpacl.Provider_Name,
	rpacl.Description,
	rpacl.Net_Price,
	rpacl.Postcode,
	rpacl.Service_Date,
	rpacl.Item_Number, 
	rpacl.Line_Item_Number,
	rpacl.Hippo_Service_Desc,
	rpacl.Source,
    COALESCE(rpacl.Membership_ID_HPC, hpc2.memberID)		as MembershipID,
    COALESCE(rpacl.Reasons_HPC, hpc2.process_remarks)		as Reasons,
    COALESCE(rpacl.Status_HPC, hpc2.claim_status)			as Status,
    COALESCE(rpacl.ProcessStatus_HPC, hpc2.process_status)  as ProcessStatus,
    fee.critical_red_lower_limit							as [Red_Lower_Limit],
    fee.critical_red_upper_limit							as [Red_Upper_Limit],
    fee.warning_blue_lower_limit							as [Blue_Lower_Limit],
    fee.warning_blue_upper_limit							as [Blue_Upper_Limit],
    hippo.Claim_Status_Type									as [MaxClaimStatus_HIPPO],
    cd.fee													as HIPPO_Fee,
    cd.benefit												as HIPPO_Benefit,
    cd.service_type											as HIPPO_ServiceType,
    cd.item_number											as HIPPO_ItemNumber,
    cover.cover_type										as CoverType,
    cover.mem_cover_at_claim								as CoverCode,
    cover.Product_Description_at_claim						as CoverDescription
FROM Claim_Lines rpacl

LEFT JOIN [BRONZE].[dbo].[rpa.HPC_ClaimsInfo] hpc2
    ON rpacl.ClaimID = hpc2.claimNumber -- to retrieve membership id for new tables

LEFT JOIN [BRONZE].[dbo].[item_averagefee] fee
    ON rpacl.Hippo_Service_Type = fee.service_type
   AND TRY_CONVERT(VARCHAR(50), rpacl.Item_Number) = TRY_CONVERT(VARCHAR(50), fee.item_number)

LEFT JOIN (Select* 
			From HIPPOLatestStatus
			Where rn = 1) hippo ON rpacl.ClaimID = TRY_CONVERT(VARCHAR(50), hippo.claim_id)

LEFT JOIN [SILVER].[dbo].[Claim_Detail_Gen_And_Hosp] cd
    ON rpacl.ClaimKey =
       CONCAT(cd.claim_id,'-',cd.claim_line_id)

LEFT JOIN [SILVER].[dbo].[ClaimDetailsAtService_optimised] cover
    ON rpacl.ClaimKey =
       CONCAT(cover.claim_id,'-',cover.claim_line_id);
