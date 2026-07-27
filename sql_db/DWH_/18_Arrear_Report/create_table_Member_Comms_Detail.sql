USE SILVER;
GO

CREATE TABLE dbo.Member_Comms_Detail (
    Membership_Id           DECIMAL(9,0)  NOT NULL,
    First_Name               VARCHAR(40)   NULL,
    Surname                  VARCHAR(40)   NULL,
    Detail_Mobile            VARCHAR(50)   NULL,
    Detail_Email             VARCHAR(50)   NULL,
    No_Contact                VARCHAR(1)    NULL,
    Postal_Preference        VARCHAR(1)    NULL,
    Email_Address             VARCHAR(100)  NULL,
    App_Registered             VARCHAR(3)    NULL,
    App_Reg_Flag               VARCHAR(25)   NULL,
    Email_Flag                 VARCHAR(10)   NULL,
    Mobile_Flag                VARCHAR(10)   NULL,
    Postal_Pref_Final          VARCHAR(5)    NULL
);
GO
