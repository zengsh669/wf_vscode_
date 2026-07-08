USE GOLD;
GO

CREATE OR ALTER VIEW dbo.vw_Agreement_Renewals
AS
SELECT DISTINCT
    [Agent ID],
    [Agency],
    [Commencement Date],
    [Expiry Date],
    [Discount Amount],
    [Agreement Status],
    [NPrint Flag],
    [Agent Name],
    [Termination Date],
    [create_operator],
    [Create Date],
    [update_operator],
    [Update Date],
    [Member Agent Term Date],
    [Member Agent Commencement Date],
    [membership_id],
    [memship_status],
    [Current PTD],
    [Ortto Key],
    [Main Member Surname],
    [LatestReceiptAmount],
    [DiscountOnLatestReceipt],
    [Discount%OnLatestReceipt],
    [Product Description],
    [Billing Frequency],
    [Group Description],
    [Expired Agreement Active Member Agent Flag],
    [Detrimental Comms Flag],
    [Member Added Within 60 Days]
FROM SILVER.dbo.AgentAgreementStatus;
GO
