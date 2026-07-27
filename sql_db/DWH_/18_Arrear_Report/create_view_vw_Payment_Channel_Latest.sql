USE GOLD;
GO

CREATE OR ALTER VIEW dbo.vw_Payment_Channel_Latest
AS
SELECT DISTINCT
    Membership_Id,
    Latest_Receipt_Type,
    Direct_Debit_Break_Down,
    Account_Number,
    Latest_Payment_Frequency
FROM SILVER.dbo.Payment_Channel;
GO
