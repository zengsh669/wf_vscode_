USE SILVER;
GO

CREATE TABLE dbo.Member_Notes (
    Membership_Id               VARCHAR(10)   NULL,
    Note_Text                   VARCHAR(7000) NULL,
    Note_Create_Date            DATETIME      NULL,
    Sub_Ref_Description         VARCHAR(15)   NULL,
    Sub_Sub_Ref_Description     VARCHAR(38)   NULL
);
GO
