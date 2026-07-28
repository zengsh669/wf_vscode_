USE GOLD;
GO

CREATE OR ALTER VIEW dbo.vw_Member_Comms_Detail
AS
SELECT
    Membership_Id,
    First_Name,
    Surname,
    Detail_Mobile,
    Detail_Email,
    No_Contact,
    Postal_Preference,
    Email_Address,
    App_Registered,
    App_Reg_Flag,
    Email_Flag,
    Mobile_Flag,
    Postal_Pref_Final
FROM SILVER.dbo.Member_Comms_Detail;
GO
