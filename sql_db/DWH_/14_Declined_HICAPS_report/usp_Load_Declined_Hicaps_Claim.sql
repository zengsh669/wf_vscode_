USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Declined_Hicaps_Claim
AS
BEGIN
    SET NOCOUNT ON;

    -- Rolling window: first day of month 24 months ago → last day of month 24 months ahead
    DECLARE @DateStart DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()) - 24, 0);
    DECLARE @DateEnd   DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()) + 25, 0); -- exclusive upper bound

    TRUNCATE TABLE SILVER.dbo.Declined_Hicaps_Claim;

    -- Latest cover version per membership (replaces Paragon_MemberCover.qvd)
    WITH MemberCoverLatest AS (
        SELECT
            membership_id,
            cover_version,
            cover_type,
            status_flag,
            cover_state,
            cover_from_date,
            termination_date,
            description         AS Cover,
            FixCode,
            Product_Description,
            ROW_NUMBER() OVER (
                PARTITION BY membership_id
                ORDER BY cover_version DESC
            ) AS rn
        FROM BRONZE.dbo.MemberCover
    )

    -- Latest note per membership (avoids row duplication where membership has multiple notes)
    , NoteLatest AS (
        SELECT *,
            ROW_NUMBER() OVER (
                PARTITION BY main_ref_id
                ORDER BY create_datetime DESC
            ) AS rn
        FROM BRONZE.dbo.note
        WHERE sub_ref_type = 'L' OR sub_ref_type_id = 76
    )

    INSERT INTO SILVER.dbo.Declined_Hicaps_Claim (
        Claim_ID,
        Claim_Line_ID,
        Membership_ID,
        Status_Date,
        Status_Date_Month_Year,
        Create_Operator,
        Assessing_Code_Type,
        Item_Number,
        Service_Type,
        Branch,
        Main_Reference_Type,
        Reference_Type,
        Reference_Create_Operator,
        Reference_Create_Date,
        Reference_Description,
        Sub_Sub_Ref_Type_ID,
        Cover_Version,
        Cover_Type,
        Status_Flag,
        Cover_State,
        Cover_From_Date,
        Termination_Date,
        Cover,
        Fix_Code,
        Product_Description
    )
    SELECT
        cl.claim_id,
        cl.claim_line_id,
        cl.membership_id,
        CAST(cl.status_date AS DATE),
        FORMAT(cl.status_date, 'MMM yyyy'),
        cl.create_operator,
        cg.assessing_code_type,
        cg.item_number,
        cg.service_type,
        ISNULL(g.description, 'MISSING')            AS Branch,
        n.main_ref_type,
        n.sub_ref_type,
        n.create_operator,
        CAST(n.create_datetime AS DATE),
        ISNULL(srt.description, 'CheckNotes')        AS Reference_Description,
        n.sub_sub_ref_type_id,
        mc.cover_version,
        mc.cover_type,
        mc.status_flag,
        mc.cover_state,
        CAST(mc.cover_from_date AS DATE),
        CAST(mc.termination_date AS DATE),
        mc.Cover,
        mc.FixCode,
        mc.Product_Description
    FROM BRONZE.dbo.claim_line AS cl

    INNER JOIN BRONZE.dbo.claim_generalitem AS cg
        ON  cg.claim_id      = cl.claim_id
        AND cg.claim_line_id = cl.claim_line_id

    -- Branch: use pre-computed SILVER table, then look up description from grouping
    LEFT JOIN SILVER.dbo.ClaimDetailsAtService_optimised AS cds
        ON  cds.claim_id      = cl.claim_id
        AND cds.claim_line_id = cl.claim_line_id
    LEFT JOIN BRONZE.dbo.grouping AS g
        ON  g.group_id   = cds.mem_branch_at_claim
        AND g.group_type = 'C'

    -- Latest note per membership only (sub_ref_type filter applied in CTE above)
    LEFT JOIN NoteLatest AS n
        ON  n.main_ref_id = CAST(cl.membership_id AS VARCHAR(20))
        AND n.rn = 1
    LEFT JOIN BRONZE.dbo.sub_ref_type AS srt
        ON  srt.sub_ref_type_id = n.sub_ref_type_id

    -- Latest cover per membership
    INNER JOIN MemberCoverLatest AS mc
        ON  mc.membership_id = cl.membership_id
        AND mc.rn = 1

    WHERE cl.status_date >= @DateStart
      AND cl.status_date <  @DateEnd
      AND cl.create_operator IN ('HICAPS', 'IBA')
      AND cg.assessing_code_type IS NOT NULL
      AND NOT (cg.item_number LIKE '6%' AND cg.service_type = 'OPTICAL');

END;
GO
