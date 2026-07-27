USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Member_Notes
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE SILVER.dbo.Member_Notes;

    INSERT INTO SILVER.dbo.Member_Notes (
        Membership_Id,
        Note_Text,
        Note_Create_Date,
        Sub_Ref_Description,
        Sub_Sub_Ref_Description
    )
    SELECT
        n.main_ref_id,
        n.note_text,
        n.create_datetime,
        sr.description,
        ssr.description
    FROM BRONZE.dbo.note AS n
    JOIN BRONZE.dbo.sub_ref_type AS sr
        ON n.sub_ref_type_id = sr.sub_ref_type_id
    LEFT JOIN BRONZE.dbo.sub_sub_ref_type AS ssr
        ON n.sub_sub_ref_type_id = ssr.sub_sub_ref_type_id
    WHERE sr.description IN ('Phone Call', 'Arrears', 'Admin-NoContact')
        AND n.main_ref_type = 'M';

END;
GO
