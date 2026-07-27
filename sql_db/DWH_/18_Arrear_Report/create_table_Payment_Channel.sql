USE SILVER;
GO

CREATE TABLE dbo.Payment_Channel (
    Membership_Id                  DECIMAL(9,0)    NOT NULL,
    Year_Month                     DATE            NOT NULL,
    Receipt_Method_Type            VARCHAR(1)      NULL,
    Receipt_Method_Desc            VARCHAR(60)     NULL,
    Total_Receipt_Amount           MONEY           NULL,
    Receipt_Count                  INT             NULL,
    Dishonour                      VARCHAR(60)     NULL,
    Dishonour_Count                INT             NULL,
    Branch_Description             VARCHAR(60)     NULL,
    Billing_Freq_Description       VARCHAR(60)     NULL,
    LOM                            INT             NULL,
    LOM_Bracket                    VARCHAR(10)     NULL,
    Date_Of_Birth                  DATE            NULL,
    Rundate                        DATE            NULL,
    Age_Bracket                    VARCHAR(10)     NULL,
    Latest_Receipt_Type            VARCHAR(60)     NULL,
    Direct_Debit_Break_Down        VARCHAR(10)     NULL,
    Account_Number                 VARCHAR(16)     NULL,
    Latest_Payment_Frequency       VARCHAR(60)     NULL
);
GO
