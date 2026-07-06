-- ============================================================
-- validate_RPA_Consolidated.sql
-- Joins the three Silver tables and maps columns to match the
-- original query output exactly (same 35 columns, same aliases).
-- Compare row count and spot-check values against the original.
-- ============================================================

SELECT
    rc.execution_id,
    rc.process_date_sydney                                              AS process_time_sydney,
    rc.MonthYear,
    rc.ClaimID,
    rc.ClaimKey,
    rc.Reasons_Display,
    rc.Sub_Reason,
    rc.Manual_Reviewer_Username,
    rc.Send_To_Open_AI,
    rc.Flag,
    rc.MemberName                                                       AS memberName,
    rc.lineID,
    rc.Provider_Number,
    rc.Provider_Name,
    rc.Description,
    rc.Net_Price,
    rc.Postcode,
    rc.Service_Date,
    rc.Item_Number,
    rc.Line_Item_Number,
    rc.Hippo_Service_Desc,
    rc.Source,
    rc.Membership_ID_HPC                                                AS MembershipID,
    rc.Reasons_HPC                                                      AS Reasons,
    rc.Status_HPC                                                       AS Status,
    rc.ProcessStatus_HPC                                                AS ProcessStatus,
    rc.Red_Lower_Limit,
    rc.Red_Upper_Limit,
    rc.Blue_Lower_Limit,
    rc.Blue_Upper_Limit,
    rc.MaxClaimStatus_HIPPO,
    cd.fee                                                              AS HIPPO_Fee,
    cd.benefit                                                          AS HIPPO_Benefit,
    cd.service_type                                                     AS HIPPO_ServiceType,
    cd.item_number                                                      AS HIPPO_ItemNumber,
    cover.cover_type                                                    AS CoverType,
    cover.mem_cover_at_claim                                            AS CoverCode,
    cover.Product_Description_at_claim                                  AS CoverDescription
FROM [SILVER].[dbo].[RPA_Consolidated] rc
LEFT JOIN [SILVER].[dbo].[Claim_Detail_Gen_And_Hosp] cd
    ON rc.ClaimKey = CONCAT(cd.claim_id, '-', cd.claim_line_id)
LEFT JOIN [SILVER].[dbo].[ClaimDetailsAtService_optimised] cover
    ON rc.ClaimKey = CONCAT(cover.claim_id, '-', cover.claim_line_id);
