USE GOLD;
GO

CREATE OR ALTER VIEW dbo.vw_Payment_Channel_By_Month
AS
SELECT
    Membership_Id,
    Year_Month,
    Receipt_Method_Type,
    Receipt_Method_Desc,
    Total_Receipt_Amount,
    Receipt_Count,
    Dishonour,
    Dishonour_Count,
    Branch_Description,
    Billing_Freq_Description,
    LOM,
    LOM_Bracket,
    Date_Of_Birth,
    Rundate,
    Age_Bracket
FROM SILVER.dbo.Payment_Channel;
GO
