USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Agent_Agreement_Renewal
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE SILVER.dbo.Agent_Agreement_Renewal;

    ;WITH
    AgentBase AS (
        SELECT
            g.group_id                             AS AgentID,
            g.group_type,
            g.description                          AS Agency,
            CAST(g.commencement_date AS DATE)      AS CommencementDate,
            CAST(g.termination_date AS DATE)       AS ExpiryDate,
            g.grp_discount_amount / 100            AS DiscountAmount
        FROM BRONZE.dbo.grouping g
        WHERE g.group_type = 'A'
    ),
    AgentStatus AS (
        SELECT
            *,
            CASE
                WHEN ExpiryDate IS NULL THEN 'Check Expiry Date'
                WHEN DATEDIFF(MINUTE, ExpiryDate, CAST(GETDATE() AS DATETIME)) < -262996 THEN 'Current'
                WHEN DATEDIFF(MINUTE, ExpiryDate, CAST(GETDATE() AS DATETIME)) > 0 THEN 'Expired'
                WHEN DATEDIFF(MINUTE, ExpiryDate, DATEADD(MINUTE, 43834, CAST(GETDATE() AS DATETIME))) > 0 THEN 'Expiring in 1 Month'
                WHEN DATEDIFF(MINUTE, ExpiryDate, DATEADD(MINUTE, 65750, CAST(GETDATE() AS DATETIME))) > 0 THEN 'Expiring in 45 Days'
                WHEN DATEDIFF(MINUTE, ExpiryDate, DATEADD(MINUTE, 87667, CAST(GETDATE() AS DATETIME))) > 0 THEN 'Expiring in 2 Months'
                WHEN DATEDIFF(MINUTE, ExpiryDate, DATEADD(MINUTE, 131501, CAST(GETDATE() AS DATETIME))) > 0 THEN 'Expiring in 3 Months'
                WHEN DATEDIFF(MINUTE, ExpiryDate, DATEADD(MINUTE, 175334, CAST(GETDATE() AS DATETIME))) > 0 THEN 'Expiring in 4 Months'
                WHEN DATEDIFF(MINUTE, ExpiryDate, DATEADD(MINUTE, 219168, CAST(GETDATE() AS DATETIME))) > 0 THEN 'Expiring in 5 Months'
                WHEN DATEDIFF(MINUTE, ExpiryDate, DATEADD(MINUTE, 262996, CAST(GETDATE() AS DATETIME))) > 0 THEN 'Expiring in 6 Months'
                ELSE 'Ok'
            END AS AgreementStatus
        FROM AgentBase
    ),
    AgentWithFlags AS (
        SELECT
            *,
            CASE WHEN AgreementStatus LIKE 'Expiring%' OR AgreementStatus LIKE 'Check%'
                 THEN 'NPrint' ELSE NULL END AS NPrintFlag
        FROM AgentStatus
    ),
    AgentAudit AS (
        SELECT
            g.group_id                             AS AgentID,
            g.description                          AS AgentName,
            CAST(g.commencement_date AS DATE)      AS AuditCommencementDate,
            CASE WHEN g.termination_date IS NULL THEN 'Active'
                 ELSE CONVERT(VARCHAR(20), CAST(g.termination_date AS DATE), 103) END AS TerminationDate,
            g.create_operator,
            CAST(g.create_datetime AS DATE)        AS CreateDate,
            g.update_operator,
            CAST(g.update_datetime AS DATE)        AS UpdateDate,
            LEFT(DATENAME(MONTH, g.create_datetime), 3) + '. ' + CAST(YEAR(g.create_datetime) AS VARCHAR(4)) AS CreateMonthyear
        FROM BRONZE.dbo.grouping g
        WHERE
            (
                DATEFROMPARTS(YEAR(g.create_datetime), MONTH(g.create_datetime), 1) <= EOMONTH(GETDATE())
                AND EOMONTH(g.create_datetime) >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
            )
            OR
            (
                (
                    DATEFROMPARTS(YEAR(g.update_datetime), MONTH(g.update_datetime), 1) <= EOMONTH(GETDATE())
                    AND EOMONTH(g.update_datetime) >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
                )
                AND g.group_type = 'A' AND g.description <> 'No Agency'
            )
    ),
    MemberAgentCTE AS (
        SELECT
            ma.group_id                            AS AgentID,
            ma.membership_id,
            CAST(ma.termination_date AS DATE)      AS MemberAgentTermDate,
            CAST(ma.commencement_date AS DATE)     AS MemberAgentCommencementDate
        FROM BRONZE.dbo.MemberAgent ma
    ),
    MemshipCTE AS (
        SELECT
            m.membership_id,
            m.memship_status,
            CAST(m.date_paidto AS DATE)            AS CurrentPTD
        FROM BRONZE.dbo.memship m
    ),
    PersonContactCTE AS (
        SELECT
            pc.membership_id,
            pc.person_id,
            CAST(pc.person_id AS VARCHAR(9)) + '-' + CAST(pc.membership_id AS VARCHAR(9)) AS OrttoKey,
            pc.surname                             AS MainMemberSurname
        FROM BRONZE.dbo.PersonContact pc
        WHERE pc.relationship = 1
    ),
    MemberCorrespondanceCTE AS (
        SELECT
            mc.membership_id,
            mc.form_id                             AS FormID,
            mc.create_datetime                     AS CorrespondanceCreateDatetime,
            CASE WHEN CAST(mc.create_datetime AS DATE) >= DATEADD(DAY, -60, CAST(GETDATE() AS DATE))
                 THEN 'Yes' ELSE 'No' END          AS HasFormGeneratedLast60Days
        FROM BRONZE.dbo.MemberCorrespondance mc
        WHERE mc.form_id IN (9114, 9115)
    ),
    ReceiptCTE AS (
        SELECT
            r.membership_id,
            r.receipt_amount                       AS LatestReceiptAmount,
            r.discount_amount                      AS DiscountOnLatestReceipt,
            r.discount_percent_used                AS DiscountPercentOnLatestReceipt
        FROM BRONZE.dbo.receipt r
        WHERE r.receipt_id = (
            SELECT MAX(r2.receipt_id)
            FROM BRONZE.dbo.receipt r2
            WHERE r2.membership_id = r.membership_id
              AND r2.receipt_amount > 0
        )
    ),
    MemberCoverCTE AS (
        SELECT
            mc.membership_id,
            mc.Product_Description                 AS ProductDescription
        FROM BRONZE.dbo.MemberCover mc
    ),
    LatestBillingVersion AS (
        SELECT membership_id, MAX(membership_group_version) AS max_version
        FROM BRONZE.dbo.membership_billing_group
        GROUP BY membership_id
    ),
    BillingFrequencyCTE AS (
        SELECT
            mbg.membership_id,
            bf.description                         AS BillingFrequency
        FROM BRONZE.dbo.membership_billing_group mbg
        JOIN LatestBillingVersion lbv
            ON lbv.membership_id = mbg.membership_id
            AND lbv.max_version = mbg.membership_group_version
        JOIN BRONZE.dbo.billing_group bg
            ON mbg.group_id = bg.group_id
        JOIN BRONZE.dbo.billing_freq bf
            ON bg.billing_freq = bf.billing_freq
    ),
    MemberGroupCTE AS (
        SELECT
            mg.membership_id,
            mg.group_id                            AS GroupID,
            mg.description                         AS GroupDescription,
            CAST(mg.commencement_date AS DATE)     AS BillingGroupCommencementDate,
            mg.membership_group_version
        FROM BRONZE.dbo.MemberGroup mg
    ),
    Assembled AS (
        SELECT
            a.AgentID                              AS [Agent ID],
            a.group_type,
            a.Agency,
            a.CommencementDate                     AS [Commencement Date],
            a.ExpiryDate                            AS [Expiry Date],
            a.DiscountAmount                       AS [Discount Amount],
            a.AgreementStatus                      AS [Agreement Status],
            a.NPrintFlag                           AS [NPrint Flag],
            aud.AgentName                          AS [Agent Name],
            aud.TerminationDate                    AS [Termination Date],
            aud.create_operator,
            aud.CreateDate                         AS [Create Date],
            aud.update_operator,
            aud.UpdateDate                         AS [Update Date],
            aud.CreateMonthyear                    AS [Create Monthyear],
            ma.MemberAgentTermDate                 AS [Member Agent Term Date],
            ma.MemberAgentCommencementDate         AS [Member Agent Commencement Date],
            ma.membership_id,
            ms.memship_status,
            ms.CurrentPTD                          AS [Current PTD],
            pc.person_id,
            pc.OrttoKey                            AS [Ortto Key],
            pc.MainMemberSurname                   AS [Main Member Surname],
            corr.FormID                            AS [Form ID],
            corr.CorrespondanceCreateDatetime      AS create_datetime,
            corr.HasFormGeneratedLast60Days        AS [Has Form Generated Last 60 Days],
            rc.LatestReceiptAmount                 AS LatestReceiptAmount,
            rc.DiscountOnLatestReceipt             AS DiscountOnLatestReceipt,
            rc.DiscountPercentOnLatestReceipt      AS [Discount%OnLatestReceipt],
            mcov.ProductDescription                AS [Product Description],
            bf.BillingFrequency                    AS [Billing Frequency],
            mg.GroupID                             AS [Group ID],
            mg.GroupDescription                    AS [Group Description],
            mg.BillingGroupCommencementDate        AS [Billing Group Commencement Date],
            mg.membership_group_version
        FROM AgentWithFlags a
        LEFT JOIN AgentAudit aud       ON aud.AgentID = a.AgentID
        LEFT JOIN MemberAgentCTE ma    ON ma.AgentID = a.AgentID
        LEFT JOIN MemshipCTE ms        ON ms.membership_id = ma.membership_id
        LEFT JOIN PersonContactCTE pc  ON pc.membership_id = ma.membership_id
        LEFT JOIN MemberCorrespondanceCTE corr ON corr.membership_id = ma.membership_id
        LEFT JOIN ReceiptCTE rc        ON rc.membership_id = ma.membership_id
        LEFT JOIN MemberCoverCTE mcov  ON mcov.membership_id = ma.membership_id
        LEFT JOIN BillingFrequencyCTE bf ON bf.membership_id = ma.membership_id
        LEFT JOIN MemberGroupCTE mg    ON mg.membership_id = ma.membership_id
    )
    INSERT INTO SILVER.dbo.Agent_Agreement_Renewal (
        [Agent ID], [group_type], [Agency], [Commencement Date], [Expiry Date], [Discount Amount],
        [Agreement Status], [NPrint Flag], [Agent Name], [Termination Date], [create_operator],
        [Create Date], [update_operator], [Update Date], [Create Monthyear],
        [Member Agent Term Date], [Member Agent Commencement Date], [membership_id], [memship_status],
        [Current PTD], [person_id], [Ortto Key], [Main Member Surname], [Form ID], [create_datetime],
        [Has Form Generated Last 60 Days], [LatestReceiptAmount], [DiscountOnLatestReceipt],
        [Discount%OnLatestReceipt], [Product Description], [Billing Frequency], [Group ID],
        [Group Description], [Billing Group Commencement Date], [membership_group_version],
        [Expired Agreement Active Member Agent Flag], [Detrimental Comms Flag], [Member Added Within 60 Days]
    )
    SELECT
        [Agent ID], [group_type], [Agency], [Commencement Date], [Expiry Date], [Discount Amount],
        [Agreement Status], [NPrint Flag], [Agent Name], [Termination Date], [create_operator],
        [Create Date], [update_operator], [Update Date], [Create Monthyear],
        [Member Agent Term Date], [Member Agent Commencement Date], [membership_id], [memship_status],
        [Current PTD], [person_id], [Ortto Key], [Main Member Surname], [Form ID], [create_datetime],
        [Has Form Generated Last 60 Days], LatestReceiptAmount, DiscountOnLatestReceipt,
        [Discount%OnLatestReceipt], [Product Description], [Billing Frequency], [Group ID],
        [Group Description], [Billing Group Commencement Date], [membership_group_version],
        CASE WHEN [Agreement Status] = 'Expired' AND [Member Agent Term Date] IS NULL
             THEN 'Flag' ELSE 'OK' END,
        CASE WHEN [Agreement Status] = 'Expiring in 45 Days' AND [Has Form Generated Last 60 Days] = 'Yes'
             THEN 'Flag' ELSE 'OK' END,
        CASE WHEN memship_status = 'A'
              AND [Expiry Date] IS NOT NULL
              AND [Member Agent Commencement Date] IS NOT NULL
              AND [Member Agent Commencement Date] >= DATEADD(DAY, -60, [Expiry Date])
              AND [Member Agent Commencement Date] <= [Expiry Date]
             THEN 'Flag' ELSE 'OK' END
    FROM Assembled;

END;
GO
