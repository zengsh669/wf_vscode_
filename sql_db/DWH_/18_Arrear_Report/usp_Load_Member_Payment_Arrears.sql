USE SILVER;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Member_Payment_Arrears
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE SILVER.dbo.Member_Payment_Arrears;

    WITH PaymentsBase AS (
        SELECT
            gk.membership_id,
            -- Qlik ApplyMap('AccountDetailsMap', membership_id, 'No Details') on account.account_type
            ISNULL(dd.account_type, 'No Details') AS DirectDebitDetails,
            CASE WHEN gk.group_id IS NULL THEN 'No Group' ELSE CAST(gk.group_id AS VARCHAR(20)) END AS GroupId,
            gk.cover,
            CASE
                WHEN gk.cover LIKE '%Athlete%'   THEN 'Athlete'
                WHEN gk.cover LIKE '%Ambulance%' THEN 'Ambulance'
                ELSE 'All other covers'
            END AS CoverCategory,
            gk.product_code,
            CAST(gk.date_paidto AS DATE)                AS date_paidto,
            gk.join_date,
            gk.member_arrears,
            gk.member_advance,
            gk.member_cont,
            CAST(DATEADD(DAY, -1, gk.rundate) AS DATE)   AS RUNDATE,
            FORMAT(DATEADD(DAY, -1, gk.rundate), 'MMM')  AS MonthYear,
            gk.member_arrears_no_other,
            gk.member_advance_no_other,
            gk.member_arrears_unearned,
            gk.member_arrears_hosp,
            gk.member_advance_hosp,
            gk.member_cont_hosp,
            gk.member_arr_unearned_hosp,
            gk.member_arrears_extras,
            gk.member_advance_extras,
            gk.member_cont_extras,
            gk.member_arr_unearned_extras,
            gk.cover_state,
            gk.branch_group_id,
            gk.branch_description,
            gk.hosp_product_id,
            gk.extras_product_id,
            gk.ambuln_product_id,
            gk.cover_type,
            gk.billing_freq,
            gk.billing_type,
            gk.member_advance_days,
            CASE
                WHEN gk.member_advance_days BETWEEN 0 AND 10   THEN '0-10 Days'
                WHEN gk.member_advance_days BETWEEN 11 AND 20  THEN '11-20 Days'
                WHEN gk.member_advance_days BETWEEN 21 AND 30  THEN '21-30 Days'
                WHEN gk.member_advance_days BETWEEN 31 AND 60  THEN '31-60 Days'
                WHEN gk.member_advance_days BETWEEN 61 AND 90  THEN '61-90 Days'
                WHEN gk.member_advance_days BETWEEN 91 AND 181 THEN '3-6 Months'
                WHEN gk.member_advance_days BETWEEN 182 AND 365 THEN '6-12 Months'
                WHEN gk.member_advance_days BETWEEN 366 AND 548 THEN '12-18 Months'
                WHEN gk.member_advance_days >= 549              THEN '> 18 Months'
            END AS AdvanceDaysBracket,
            gk.member_arrears_days,
            CASE
                WHEN gk.member_arrears_days <= 0 THEN 'Not in Arrears'
                WHEN gk.member_arrears_days BETWEEN 0 AND 10   THEN '0-10'
                WHEN gk.member_arrears_days BETWEEN 11 AND 20  THEN '11-20'
                WHEN gk.member_arrears_days BETWEEN 21 AND 30  THEN '21-30'
                WHEN gk.member_arrears_days BETWEEN 31 AND 60  THEN '31-60'
                WHEN gk.member_arrears_days BETWEEN 61 AND 90  THEN '61-90'
                WHEN gk.member_arrears_days >= 91               THEN '91+'
            END AS ArrearsDaysBracket,
            gk.sales_channel_description,
            gk.billing_freq_description,
            gk.hear_about_description,
            gk.promotion_description,
            gk.agent_description,
            gk.billing_group_description,
            gk.previous_fund_id,
            gk.previous_fund_description,
            CASE
                WHEN gk.billing_group_description LIKE '%Direct Debit%' THEN 'Direct Debit'
                WHEN gk.billing_group_description LIKE '%Direct Pay%'   THEN 'Direct Payer'
                WHEN gk.billing_group_description LIKE '%Deceased%'     THEN 'Deceased Members'
                ELSE 'Payroll Group'
            END AS PayingType,
            m.memship_status,
            CAST(m.effective_termination_date AS DATE)  AS TerminationDate,
            CAST(m.entry_term_date AS DATE)              AS EntryTerminationDate,
            bg.tpt_period                                AS NoPeriods,
            bf.description                               AS PeriodDescription
        FROM BRONZE.dbo.group_key_full_by_branch AS gk
        INNER JOIN BRONZE.dbo.memship AS m
            ON gk.membership_id = m.membership_id
        LEFT OUTER JOIN BRONZE.dbo.billing_group AS bg
            ON gk.group_id = bg.group_id
        LEFT OUTER JOIN BRONZE.dbo.billing_freq AS bf
            ON bg.billing_freq = bf.billing_freq
        LEFT JOIN BRONZE.dbo.account AS dd
            ON gk.membership_id = dd.membership_id
            AND dd.account_type = 'D' AND dd.status_flag = 'A'
        WHERE gk.rundate > '2025-01-01'
    ),
    PaymentsPeriod AS (
        SELECT
            *,
            CASE
                WHEN PeriodDescription = 'Weekly'      THEN DATEADD(DAY, 7 * NoPeriods, date_paidto)
                WHEN PeriodDescription = 'Fortnightly'  THEN DATEADD(DAY, 14 * NoPeriods, date_paidto)
                WHEN PeriodDescription = 'Monthly'      THEN DATEADD(MONTH, NoPeriods, date_paidto)
                ELSE date_paidto
            END AS TPT_DATE
        FROM PaymentsBase
    ),
    PaymentsFlags AS (
        SELECT
            *,
            CASE WHEN TPT_DATE >= RUNDATE THEN 'Advance' ELSE 'Arrears' END AS AdvanceArrearsFlag,
            CASE WHEN TPT_DATE < RUNDATE THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS ArrearsFlag,
            DATEFROMPARTS(YEAR(RUNDATE), MONTH(RUNDATE), 1) AS ArrearsMonth
        FROM PaymentsPeriod
    ),
    PaymentsTermFlags AS (
        SELECT
            *,
            CASE
                WHEN YEAR(TerminationDate) = YEAR(ArrearsMonth) AND MONTH(TerminationDate) = MONTH(ArrearsMonth)
                    THEN 'Termination Month Flag'
                ELSE 'Did not Term this month'
            END AS TerminationMonthFlag,
            CASE
                WHEN DATEDIFF(DAY, TerminationDate, EntryTerminationDate) >= 60
                    THEN '60 days backdated'
                ELSE NULL
            END AS SixtyDaysBackdated
        FROM PaymentsFlags
    ),
    PaymentsWithChange AS (
        SELECT
            *,
            CASE
                WHEN membership_id = LAG(membership_id) OVER (ORDER BY membership_id, RUNDATE)
                     AND PayingType <> LAG(PayingType) OVER (ORDER BY membership_id, RUNDATE)
                THEN
                    CASE
                        WHEN PayingType = 'Direct Payer' THEN 'Changed From DD to DP'
                        WHEN PayingType = 'Direct Debit'  THEN 'Changed From DP to DD'
                        ELSE NULL
                    END
                ELSE 'Did not Change'
            END AS PaymentChange
        FROM PaymentsTermFlags
    ),
    ConsecMonths AS (
        SELECT
            membership_id,
            ArrearsMonth,
            SUM(CASE WHEN ArrearsFlag = 1 THEN 1 ELSE 0 END) OVER (
                PARTITION BY membership_id, grp
                ORDER BY ArrearsMonth
                ROWS UNBOUNDED PRECEDING
            ) AS ConsecMonths
        FROM (
            SELECT
                membership_id,
                ArrearsMonth,
                ArrearsFlag,
                SUM(CASE WHEN ArrearsFlag = 0 THEN 1 ELSE 0 END) OVER (
                    PARTITION BY membership_id ORDER BY ArrearsMonth ROWS UNBOUNDED PRECEDING
                ) AS grp
            FROM PaymentsWithChange
        ) AS gapped
    ),
    DishonoursMonthly AS (
        SELECT
            r.membership_id,
            DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1) AS DishonourMonth,
            COUNT(rmt.description) AS CountofDishonours
        FROM BRONZE.dbo.receipt AS r
        JOIN BRONZE.dbo.receipt_method AS rm
            ON r.receipt_link_id = rm.receipt_link_id
        LEFT JOIN BRONZE.dbo.receipt_method_type AS rmt
            ON rm.receipt_method_type = rmt.receipt_method_type
        WHERE r.create_datetime >= '2025-01-01' AND rmt.description = 'Dishonour'
        GROUP BY r.membership_id, DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1)
    )

    INSERT INTO SILVER.dbo.Member_Payment_Arrears (
        Mbr_Month_Key,
        Membership_Id,
        Direct_Debit_Details,
        Group_Id,
        Cover,
        Cover_Category,
        Product_Code,
        Date_Paid_To,
        Join_Date,
        Member_Arrears,
        Member_Advance,
        Member_Cont,
        Rundate,
        Month_Year,
        Member_Arrears_No_Other,
        Member_Advance_No_Other,
        Member_Arrears_Unearned,
        Member_Arrears_Hosp,
        Member_Advance_Hosp,
        Member_Cont_Hosp,
        Member_Arr_Unearned_Hosp,
        Member_Arrears_Extras,
        Member_Advance_Extras,
        Member_Cont_Extras,
        Member_Arr_Unearned_Extras,
        Cover_State,
        Branch_Group_Id,
        Branch_Description,
        Hosp_Product_Id,
        Extras_Product_Id,
        Ambuln_Product_Id,
        Cover_Type,
        Billing_Freq,
        Billing_Type,
        Member_Advance_Days,
        Advance_Days_Bracket,
        Member_Arrears_Days,
        Arrears_Days_Bracket,
        Sales_Channel_Description,
        Billing_Freq_Description,
        Hear_About_Description,
        Promotion_Description,
        Agent_Description,
        Billing_Group_Description,
        Previous_Fund_Id,
        Previous_Fund_Description,
        Paying_Type,
        Memship_Status,
        Termination_Date,
        Entry_Termination_Date,
        No_Periods,
        Period_Description,
        TPT_Date,
        Advance_Arrears_Flag,
        Arrears_Flag,
        Mbr_Arrears_Key,
        Arrears_Month,
        Termination_Month_Flag,
        Sixty_Days_Backdated,
        Payment_Change,
        Count_Of_Dishonours,
        Dishonour_Type,
        Consec_Months
    )
    SELECT
        CAST(p.membership_id AS VARCHAR(20)) + '|' + CONVERT(VARCHAR(10), p.ArrearsMonth, 120),
        p.membership_id,
        p.DirectDebitDetails,
        p.GroupId,
        p.cover,
        p.CoverCategory,
        p.product_code,
        p.date_paidto,
        p.join_date,
        p.member_arrears,
        p.member_advance,
        p.member_cont,
        p.RUNDATE,
        p.MonthYear,
        p.member_arrears_no_other,
        p.member_advance_no_other,
        p.member_arrears_unearned,
        p.member_arrears_hosp,
        p.member_advance_hosp,
        p.member_cont_hosp,
        p.member_arr_unearned_hosp,
        p.member_arrears_extras,
        p.member_advance_extras,
        p.member_cont_extras,
        p.member_arr_unearned_extras,
        p.cover_state,
        p.branch_group_id,
        p.branch_description,
        p.hosp_product_id,
        p.extras_product_id,
        p.ambuln_product_id,
        p.cover_type,
        p.billing_freq,
        p.billing_type,
        p.member_advance_days,
        p.AdvanceDaysBracket,
        p.member_arrears_days,
        p.ArrearsDaysBracket,
        p.sales_channel_description,
        p.billing_freq_description,
        p.hear_about_description,
        p.promotion_description,
        p.agent_description,
        p.billing_group_description,
        p.previous_fund_id,
        p.previous_fund_description,
        p.PayingType,
        p.memship_status,
        p.TerminationDate,
        p.EntryTerminationDate,
        p.NoPeriods,
        p.PeriodDescription,
        p.TPT_DATE,
        p.AdvanceArrearsFlag,
        p.ArrearsFlag,
        CAST(p.membership_id AS VARCHAR(20)) + '|' + CONVERT(VARCHAR(10), p.ArrearsMonth, 120),
        p.ArrearsMonth,
        p.TerminationMonthFlag,
        p.SixtyDaysBackdated,
        p.PaymentChange,
        dh.CountofDishonours,
        CASE
            WHEN dh.CountofDishonours = 1 THEN 'Dishonour 1'
            WHEN dh.CountofDishonours > 1 THEN 'Dishonour >1'
            ELSE 'No Dishonour'
        END,
        cm.ConsecMonths
    FROM PaymentsWithChange AS p
    LEFT JOIN ConsecMonths AS cm
        ON p.membership_id = cm.membership_id AND p.ArrearsMonth = cm.ArrearsMonth
    LEFT JOIN DishonoursMonthly AS dh
        ON p.membership_id = dh.membership_id AND p.ArrearsMonth = dh.DishonourMonth;

END;
GO
