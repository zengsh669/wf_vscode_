USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Payment_Channel
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE dbo.Payment_Channel;

    WITH ReceiptMonthly AS (
        -- Qlik Section3 base: monthly receipt aggregation per membership + method type
        SELECT
            r.membership_id,
            DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1) AS YearMonth,
            rm.receipt_method_type,
            rmt.description AS ReceiptMethodDesc,
            SUM(r.receipt_amount) AS TotalReceiptAmount,
            COUNT(r.receipt_id) AS ReceiptCount
        FROM BRONZE.dbo.memship AS m
        JOIN BRONZE.dbo.receipt AS r
            ON r.membership_id = m.membership_id
        JOIN BRONZE.dbo.receipt_method AS rm
            ON r.receipt_link_id = rm.receipt_link_id
        JOIN BRONZE.dbo.receipt_method_type AS rmt
            ON rm.receipt_method_type = rmt.receipt_method_type
        WHERE m.memship_status = 'A'
            AND rm.receipt_method_type NOT IN ('l','O','r','m','c','3','d','n','p','v','1','f','V','u','A','R','j')
            AND r.create_datetime >= '2025-01-01'
        GROUP BY
            r.membership_id,
            DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1),
            rm.receipt_method_type,
            rmt.description
    ),
    DishonourMonthly AS (
        -- Qlik Dishonour: same shape, filtered to receipt_method_type = 'A'
        SELECT
            r.membership_id,
            DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1) AS YearMonth,
            rmt.description AS Dishonour,
            COUNT(r.receipt_id) AS DishonourCount
        FROM BRONZE.dbo.memship AS m
        JOIN BRONZE.dbo.receipt AS r
            ON r.membership_id = m.membership_id
        JOIN BRONZE.dbo.receipt_method AS rm
            ON r.receipt_link_id = rm.receipt_link_id
        JOIN BRONZE.dbo.receipt_method_type AS rmt
            ON rm.receipt_method_type = rmt.receipt_method_type
        WHERE m.memship_status = 'A'
            AND rm.receipt_method_type = 'A'
            AND r.create_datetime >= '2025-01-01'
        GROUP BY
            r.membership_id,
            DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1),
            rmt.description
    ),
    Characteristics AS (
        -- Qlik Characteristics: branch/billing_freq/LOM as of PriorMonth (rundate - 1 month)
        SELECT
            gk.membership_id,
            gk.rundate,
            DATEFROMPARTS(YEAR(DATEADD(MONTH, -1, gk.rundate)), MONTH(DATEADD(MONTH, -1, gk.rundate)), 1) AS PriorMonth,
            gk.branch_description,
            gk.billing_freq_description,
            DATEDIFF(YEAR, gk.join_date, gk.rundate)
                - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, gk.join_date, gk.rundate), gk.join_date) > gk.rundate THEN 1 ELSE 0 END AS LOM,
            pb.date_of_birth
        FROM BRONZE.dbo.group_key_full_by_branch AS gk
        LEFT JOIN BRONZE.dbo.person_membership AS pm
            ON pm.membership_id = gk.membership_id
            AND pm.relationship = '1'
            AND pm.status_flag = 'A'
        LEFT JOIN BRONZE.dbo.person AS pb
            ON pb.person_id = pm.person_id
        WHERE gk.rundate >= '2025-01-01'
    ),
    LatestReceipt AS (
        -- Qlik LatestMembership base: single latest receipt row per membership
        SELECT
            r.membership_id,
            rmt.description AS LatestReceiptType,
            ROW_NUMBER() OVER (PARTITION BY r.membership_id ORDER BY r.create_datetime DESC) AS rn
        FROM BRONZE.dbo.memship AS m
        JOIN BRONZE.dbo.receipt AS r
            ON r.membership_id = m.membership_id
        JOIN BRONZE.dbo.receipt_method AS rm
            ON r.receipt_link_id = rm.receipt_link_id
        JOIN BRONZE.dbo.receipt_method_type AS rmt
            ON rm.receipt_method_type = rmt.receipt_method_type
        WHERE m.memship_status = 'A'
            AND rm.receipt_method_type NOT IN ('l','O','r','m','c','3','d','n','p','v','1','f','V','u','A','R','j')
    ),
    DirectDebit AS (
        -- Qlik DirectDebit load
        SELECT
            a.membership_id,
            CASE
                WHEN a.expiry_date IS NULL THEN 'Account'
                WHEN a.expiry_date < CAST(GETDATE() AS DATE) THEN 'Account'
                ELSE 'Card'
            END AS DirectDebitBreakDown,
            a.account_number
        FROM BRONZE.dbo.memship AS m
        JOIN BRONZE.dbo.account AS a
            ON m.membership_id = a.membership_id
        WHERE a.status_flag = 'A' AND a.account_type = 'D'
    ),
    LatestPaymentFreq AS (
        -- Inlined from paragonreporting view dbo.MemberPaymentFrequencyLatest
        SELECT
            mbg.membership_id,
            bf.description AS LatestPaymentFrequency
        FROM BRONZE.dbo.membership_billing_group AS mbg
        JOIN BRONZE.dbo.billing_group AS bg
            ON mbg.group_id = bg.group_id
        JOIN BRONZE.dbo.billing_freq AS bf
            ON bg.billing_freq = bf.billing_freq
        WHERE mbg.membership_group_version = (
            SELECT MAX(bg2.membership_group_version)
            FROM BRONZE.dbo.membership_billing_group AS bg2
            WHERE bg2.membership_id = mbg.membership_id
        )
    )

    INSERT INTO dbo.Payment_Channel (
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
        Age_Bracket,
        Latest_Receipt_Type,
        Direct_Debit_Break_Down,
        Account_Number,
        Latest_Payment_Frequency
    )
    SELECT
        rmly.membership_id,
        rmly.YearMonth,
        rmly.receipt_method_type,
        rmly.ReceiptMethodDesc,
        rmly.TotalReceiptAmount,
        rmly.ReceiptCount,
        dh.Dishonour,
        dh.DishonourCount,
        ch.branch_description,
        ch.billing_freq_description,
        ch.LOM,
        CASE
            WHEN ch.LOM <= 3 THEN '0-3yrs'
            WHEN ch.LOM > 3 AND ch.LOM <= 5 THEN '3-5yrs'
            WHEN ch.LOM > 5 AND ch.LOM <= 10 THEN '5-10yrs'
            WHEN ch.LOM > 10 THEN '10yrs+'
        END,
        ch.date_of_birth,
        -- Age computed against rundate (matches Qlik age(rundate, date_of_birth)), with anniversary adjustment consistent with the LOM calculation above.
        -- NOTE: mirrors Qlik source's age-bracket logic, which re-tests LOM (not age) in the later branches — preserved as-is per faithfulness to source, not corrected
        CASE
            WHEN (DATEDIFF(YEAR, ch.date_of_birth, ch.rundate)
                - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, ch.date_of_birth, ch.rundate), ch.date_of_birth) > ch.rundate THEN 1 ELSE 0 END) <= 25 THEN '<25yrs'
            WHEN (DATEDIFF(YEAR, ch.date_of_birth, ch.rundate)
                - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, ch.date_of_birth, ch.rundate), ch.date_of_birth) > ch.rundate THEN 1 ELSE 0 END) > 25 AND ch.LOM <= 35 THEN '25-35yrs'
            WHEN (DATEDIFF(YEAR, ch.date_of_birth, ch.rundate)
                - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, ch.date_of_birth, ch.rundate), ch.date_of_birth) > ch.rundate THEN 1 ELSE 0 END) > 35 AND ch.LOM <= 45 THEN '35-45yrs'
            WHEN (DATEDIFF(YEAR, ch.date_of_birth, ch.rundate)
                - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, ch.date_of_birth, ch.rundate), ch.date_of_birth) > ch.rundate THEN 1 ELSE 0 END) > 45 AND ch.LOM <= 55 THEN '45-55yrs'
            WHEN (DATEDIFF(YEAR, ch.date_of_birth, ch.rundate)
                - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, ch.date_of_birth, ch.rundate), ch.date_of_birth) > ch.rundate THEN 1 ELSE 0 END) > 55 AND ch.LOM <= 65 THEN '55-65yrs'
            WHEN (DATEDIFF(YEAR, ch.date_of_birth, ch.rundate)
                - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, ch.date_of_birth, ch.rundate), ch.date_of_birth) > ch.rundate THEN 1 ELSE 0 END) > 65 THEN '65yrs+'
        END,
        lr.LatestReceiptType,
        dd.DirectDebitBreakDown,
        dd.account_number,
        lpf.LatestPaymentFrequency
    FROM ReceiptMonthly AS rmly
    LEFT JOIN DishonourMonthly AS dh
        ON rmly.membership_id = dh.membership_id AND rmly.YearMonth = dh.YearMonth
    LEFT JOIN Characteristics AS ch
        ON rmly.membership_id = ch.membership_id AND rmly.YearMonth = ch.PriorMonth
    LEFT JOIN LatestReceipt AS lr
        ON rmly.membership_id = lr.membership_id AND lr.rn = 1
    LEFT JOIN DirectDebit AS dd
        ON rmly.membership_id = dd.membership_id
    LEFT JOIN LatestPaymentFreq AS lpf
        ON rmly.membership_id = lpf.membership_id;

END;
GO
