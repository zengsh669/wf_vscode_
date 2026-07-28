USE GOLD;
GO

CREATE OR ALTER VIEW dbo.vw_Member_Notes
AS
SELECT
    Membership_Id,
    Note_Text,
    Note_Create_Date,
    Sub_Ref_Description,
    Sub_Sub_Ref_Description
FROM SILVER.dbo.Member_Notes;
GO
