USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.Load_ArrearsReportPayroll
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE dbo.Arrears_Report;

    WITH ArrearsBase AS (
        SELECT
            m.membership_id                             AS [Membership ID],
            m.memship_status,
            CAST(m.date_paidto AS DATE)                 AS [Date Paid To],
            ISNULL(s.description, 'Unknown')            AS [Security Level]
        FROM BRONZE.dbo.memship AS m
        LEFT JOIN BRONZE.dbo.security_level AS s
            ON m.security_level = s.security_level
        WHERE m.memship_status = 'A'
    ),
    JoinedData AS (
        SELECT
            a.[Membership ID],
            a.memship_status,
            a.[Date Paid To],
            a.[Security Level],
            pm.person_id,
            pm.relationship,
            mb.description                              AS Branch,
            mc.FixCode,
            mc.Product_Description,
            mg.group_id,
            p.surname,
            p.first_name,
            p.first_name + ' ' + p.surname             AS name,
            g.description                              AS GroupingDesc,
            bg.billing_type,
            bg.billing_freq,
            bg.tpt_period                              AS [Tpt Period],
            ma.description                             AS AgentDesc,
            ws.postal_preference                       AS [Post Preference],
            ws.main_ref_type                           AS [Main Ref Type]
        FROM ArrearsBase AS a
        LEFT JOIN BRONZE.dbo.person_membership AS pm
            ON a.[Membership ID] = pm.membership_id
            AND pm.relationship = 1
        LEFT JOIN BRONZE.dbo.MemberBranch AS mb
            ON a.[Membership ID] = mb.membership_id
        LEFT JOIN BRONZE.dbo.MemberCover AS mc
            ON a.[Membership ID] = mc.membership_id
        LEFT JOIN BRONZE.dbo.MemberGroup AS mg
            ON a.[Membership ID] = mg.membership_id
        LEFT JOIN BRONZE.dbo.person AS p
            ON pm.person_id = p.person_id
        LEFT JOIN BRONZE.dbo.grouping AS g
            ON mg.group_id = g.group_id
        LEFT JOIN BRONZE.dbo.billing_group AS bg
            ON mg.group_id = bg.group_id
        LEFT JOIN BRONZE.dbo.MemberAgent AS ma
            ON a.[Membership ID] = ma.membership_id
        LEFT JOIN BRONZE.dbo.web_security AS ws
            ON pm.person_id = ws.main_ref_id AND ws.membership_id = pm.membership_id
            AND ws.main_ref_type = 'P'
    ),
    RegisteredMO AS (
        SELECT
            j.*,
            CASE
                WHEN j.[Post Preference] = 'E' THEN 'Email'
                WHEN j.[Post Preference] = 'P' THEN 'Postal'
                ELSE 'Not Registered to MO'
            END AS [Postal Preference]
        FROM JoinedData AS j
    ),
    BillingTypeJoin AS (
        SELECT
            r.*,
            bt.description AS BillingDes,
            CASE
                WHEN bt.description = 'Payroll'          THEN 'Payroll'
                WHEN bt.description LIKE '%Direct%'      THEN 'Direct Debit/Payer'
                ELSE 'Other'
            END AS [Payment Type]
        FROM RegisteredMO AS r
        INNER JOIN BRONZE.dbo.billing_type AS bt
            ON r.billing_type = bt.billing_type
    ),
    BillingFreqMap AS (
        SELECT *
        FROM (VALUES
            (0, 'd', 1),
            (1, 'd', 7),
            (2, 'd', 14),
            (3, 'd', 28),
            (4, 'm', 1),
            (5, 'm', 2),
            (6, 'm', 3),
            (7, 'm', 6),
            (8, 'm', 12),
            (9, 'd', 1)
        ) AS f(billing_freq, typebill, amount)
    ),
    Bucket1 AS (
        SELECT
            b.*,
            f.typebill,
            f.amount,
            CASE
                WHEN b.[Security Level] = 'No Access Restrictions' THEN b.name
                ELSE b.[Security Level]
            END AS [Name],
            CASE
                WHEN f.typebill = 'd' THEN DATEADD(DAY,   f.amount * b.[Tpt Period], b.[Date Paid To])
                WHEN f.typebill = 'm' THEN DATEADD(MONTH, f.amount * b.[Tpt Period], b.[Date Paid To])
            END AS [tpt_day],
            CASE
                WHEN b.Product_Description = 'Ambulance' THEN 'Ambulance Product'
                ELSE 'Non Ambulance Products'
            END AS [Directdebitfilter]
        FROM BillingTypeJoin AS b
        INNER JOIN BillingFreqMap AS f
            ON b.billing_freq = f.billing_freq
    ),
    Bucket2 AS (
        SELECT
            *,
            DATEDIFF(DAY, [Date Paid To], CAST(GETDATE() AS DATE))                         AS [DaysInArrears],
            CAST(GETDATE() AS DATE)                                                         AS [Run Date],
            FORMAT(DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1), 'MMM yyyy')        AS [Run Month]
        FROM Bucket1
    ),
    Bucket3 AS (
        SELECT
            *,
            CASE
                WHEN [DaysInArrears] > 57                        THEN '58 Days plus in arrears'
                WHEN [DaysInArrears] BETWEEN 45 AND 57           THEN '45-57 Days in arrears'
                WHEN [DaysInArrears] BETWEEN 30 AND 44           THEN '30-44 Days in arrears'
                WHEN [DaysInArrears] BETWEEN 15 AND 29           THEN '15-29 Days in arrears'
                WHEN [DaysInArrears] BETWEEN 1  AND 14           THEN 'Less than 15 Days in arrears'
                ELSE 'No Arrears'
            END AS [Arrears Category]
        FROM Bucket2
    )

    INSERT INTO dbo.Arrears_Report (
        [Membership ID],
        memship_status,
        [Date Paid To],
        [Security Level],
        person_id,
        relationship,
        Branch,
        FixCode,
        Product_Description,
        group_id,
        surname,
        first_name,
        name,
        GroupingDesc,
        billing_type,
        billing_freq,
        [Tpt Period],
        AgentDesc,
        [Post Preference],
        [Main Ref Type],
        BillingDes,
        [Payment Type],
        typebill,
        amount,
        tpt_day,
        Directdebitfilter,
        [DaysInArrears],
        [Run Date],
        [Run Month],
        [Arrears Category]
    )
    SELECT
        [Membership ID],
        memship_status,
        [Date Paid To],
        [Security Level],
        CAST(person_id   AS NVARCHAR(50)),
        CAST(relationship AS NVARCHAR(10)),
        Branch,
        FixCode,
        Product_Description,
        CAST(group_id    AS NVARCHAR(50)),
        surname,
        first_name,
        name,
        GroupingDesc,
        billing_type,
        CAST(billing_freq  AS NVARCHAR(10)),
        CAST([Tpt Period]  AS NVARCHAR(10)),
        AgentDesc,
        [Postal Preference],
        [Main Ref Type],
        BillingDes,
        [Payment Type],
        typebill,
        CAST(amount        AS NVARCHAR(10)),
        tpt_day,
        Directdebitfilter,
        CAST([DaysInArrears] AS NVARCHAR(10)),
        [Run Date],
        [Run Month],
        [Arrears Category]
    FROM Bucket3;

END;
GO
