USE [SILVER]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[usp_Load_Earned_Contributions]
    @StartMonth  date = '2026-05-01',        -- First CurrentMonth to process; defaults to current month (single-month run)
    @CurrRI      date = '2026-04-01' -- Current Rate Increase date; update annually
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. 日期变量初始化
    DECLARE @EndMonth date = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);

    IF @StartMonth IS NULL
        SET @StartMonth = @EndMonth;  -- 默认只跑上个月（现有行为）

    DECLARE @LoopMonth      date;
    DECLARE @PreviousMonth  date;
    DECLARE @ReportMonth    date;
    DECLARE @ReportMonthEnd date;
    DECLARE @PrevRI         date = DATEADD(YEAR, -1, @CurrRI);  -- 不随循环变化，声明一次

    -- 2. 清空目标表（只执行一次）
    TRUNCATE TABLE dbo.Earned_Contributions;

    -- 3. 预计算费率（不依赖循环月份，提到循环外）
    SELECT
        cover_state, cover_type, product_id,
        ISNULL(CAST(MAX(CASE WHEN fee_from_date <= @CurrRI THEN product_fee_amount * 52.0 / 12 END) AS decimal(18,2)), 0) AS curr_mrate, --changed to <= on 13/05 per requested
        ISNULL(CAST(MAX(CASE WHEN fee_from_date <= @PrevRI THEN product_fee_amount * 52.0 / 12 END) AS decimal(18,2)), 0) AS prev_mrate  --changed to <= on 13/05 per requested
    INTO #product_rates
    FROM BRONZE.dbo.product_fee
    GROUP BY cover_state, cover_type, product_id;

    -- 4. 按月循环
    SET @LoopMonth = @StartMonth;

    WHILE @LoopMonth <= @EndMonth
    BEGIN
        SET @PreviousMonth  = DATEADD(MONTH, -1, @LoopMonth);
        SET @ReportMonth    = @PreviousMonth;
        SET @ReportMonthEnd = EOMONTH(@ReportMonth);

        -- 核心计算逻辑
        WITH Advances_Arrears AS (
            SELECT
                a.membership_id,
                @ReportMonth AS Month_Year,
                (ISNULL(b.member_arrears, 0) - ISNULL(c.member_arrears, 0)) AS Net_Arrears,
                (ISNULL(b.member_advance, 0) - ISNULL(c.member_advance, 0)) AS Net_Advance
            FROM (SELECT DISTINCT membership_id FROM BRONZE.dbo.group_key_full_by_branch WHERE rundate BETWEEN @PreviousMonth AND @LoopMonth) a
            LEFT OUTER JOIN BRONZE.dbo.group_key_full_by_branch b
                ON a.membership_id = b.membership_id AND b.rundate = @LoopMonth
            LEFT OUTER JOIN BRONZE.dbo.group_key_full_by_branch c
                ON a.membership_id = c.membership_id AND c.rundate = @PreviousMonth
        ),

        Receipts_raw AS (
            SELECT
                r.membership_id,
                ISNULL(r.con_discount_pct, 0) / 100 AS con_discount,
                CAST((r.receipt_amount + r.rebate_amount) AS decimal(18,2)) AS received_amount,
                CAST((ISNULL(r.receipt_amount_bonus, 0) + ISNULL(r.rebate_amount_bonus, 0)) AS decimal(18,2)) AS bonus_amount
            FROM BRONZE.dbo.receipt AS r
            INNER JOIN BRONZE.dbo.receipt_status rs
                ON r.receipt_id = rs.receipt_id AND r.membership_id = rs.membership_id
            WHERE r.create_datetime >= @ReportMonth
              AND r.create_datetime < DATEADD(DAY, 1, @ReportMonthEnd)
              AND rs.receipt_status_type IN ('P', 'U', 'A')
        ),

        Monthly_receipts AS (
            SELECT
                membership_id,
                MAX(con_discount) AS con_discount,
                SUM(received_amount) AS received_amount,
                SUM(bonus_amount) AS bonus_amount
            FROM Receipts_raw
            GROUP BY membership_id
        ),

        All_contributions AS (
            SELECT
                COALESCE(mr.membership_id, aa.membership_id) AS membership_id,
                @ReportMonth AS Month_Year,
                ISNULL(mr.received_amount, 0) AS received_amount,
                ISNULL(mr.bonus_amount, 0)    AS bonus_amount,
                ISNULL(aa.Net_Advance, 0)     AS Net_Advance,
                ISNULL(aa.Net_Arrears, 0)     AS Net_Arrears,
                ISNULL(mr.con_discount, 0)    AS con_discount
            FROM Monthly_receipts mr
            FULL OUTER JOIN Advances_Arrears aa
                ON mr.membership_id = aa.membership_id
        ),

        Max_cover_version AS (
            SELECT cp.membership_id, MAX(cp.cover_version) AS max_cv
            FROM BRONZE.dbo.cover_product cp
            INNER JOIN BRONZE.dbo.cover c
                ON c.membership_id = cp.membership_id AND c.cover_version = cp.cover_version
            WHERE c.cover_from_date <= @LoopMonth
            GROUP BY cp.membership_id
        ),

        Member_details AS (
            SELECT
                cp.membership_id, cp.cover_version, cp.product_id,
                p.product_type,
                c.cover_type, c.cover_state
            FROM BRONZE.dbo.cover_product cp
            INNER JOIN Max_cover_version mcv
                ON cp.membership_id = mcv.membership_id AND cp.cover_version = mcv.max_cv
            LEFT OUTER JOIN BRONZE.dbo.product p
                ON cp.product_id = p.product_id
            LEFT OUTER JOIN BRONZE.dbo.cover c
                ON c.membership_id = cp.membership_id AND c.cover_version = cp.cover_version
        ),

        DRL AS (
            SELECT
                m.membership_id,
                (m.member1_loading / 100) AS mem1_loading,
                (m.member2_loading / 100) AS mem2_loading,
                ISNULL(m.overall_agediscount, 0) / 100 AS overall_agediscount,
                ISNULL(gr.grp_discount_amount, 0) / 100 AS corporate_discount
            FROM BRONZE.dbo.memship m
            LEFT OUTER JOIN BRONZE.dbo.memship_app_agent ma ON m.membership_id = ma.membership_id
            LEFT OUTER JOIN BRONZE.dbo.grouping gr ON ma.agent_group_id = gr.group_id
            WHERE m.memship_status NOT IN ('L', 'P')
        ),

        Combined_data AS (
            SELECT
                ac.*,
                (received_amount + bonus_amount + Net_Arrears - Net_Advance) AS earned_contributions,
                ISNULL(MAX(CASE WHEN md.product_type = 'H' THEN md.product_id END), 0) AS H_prod,
                ISNULL(MAX(CASE WHEN md.product_type = 'A' THEN md.product_id END), 0) AS A_prod,
                ISNULL(MAX(CASE WHEN md.product_type = 'B' THEN md.product_id END), 0) AS B_prod,
                md.cover_type,
                md.cover_state,
                CASE WHEN md.cover_type IN ('A', 'B', 'P', 'S') THEN d.mem1_loading ELSE (d.mem1_loading + d.mem2_loading) / 2 END AS overall_lhc,
                d.overall_agediscount,
                d.corporate_discount
            FROM All_contributions ac
            LEFT OUTER JOIN Member_details md
                ON md.membership_id = ac.membership_id
            LEFT OUTER JOIN DRL d
                ON ac.membership_id = d.membership_id
            GROUP BY
                ac.membership_id, ac.Month_Year, ac.received_amount, ac.bonus_amount,
                ac.Net_Advance, ac.Net_Arrears, md.cover_type, md.cover_state,
                ac.con_discount, d.overall_agediscount, d.corporate_discount,
                d.mem1_loading, d.mem2_loading
        ),

        Latest_payment_date AS (
            SELECT membership_id, MAX(old_paid_to) AS old_paidto
            FROM BRONZE.dbo.receipt
            WHERE create_datetime >= EOMONTH(@LoopMonth, -24)
            GROUP BY membership_id
        ),

        All_Data AS (
            SELECT
                a.*, c.old_paidto,
                CASE WHEN c.old_paidto < @CurrRI THEN 1 ELSE 0 END AS RP_flag,
                ISNULL(b1.curr_mrate, 0) AS curr_H_rate, ISNULL(b1.prev_mrate, 0) AS prev_H_rate,
                ISNULL(b2.curr_mrate, 0) AS curr_A_rate, ISNULL(b2.prev_mrate, 0) AS prev_A_rate,
                ISNULL(b3.curr_mrate, 0) AS curr_B_rate, ISNULL(b3.prev_mrate, 0) AS prev_B_rate
            FROM Combined_data a
            LEFT OUTER JOIN Latest_payment_date c ON a.membership_id = c.membership_id
            LEFT OUTER JOIN #product_rates b1 ON a.cover_state = b1.cover_state AND a.cover_type = b1.cover_type AND b1.product_id = a.H_prod
            LEFT OUTER JOIN #product_rates b2 ON a.cover_state = b2.cover_state AND a.cover_type = b2.cover_type AND b2.product_id = a.A_prod
            LEFT OUTER JOIN #product_rates b3 ON a.cover_state = b3.cover_state AND a.cover_type = b3.cover_type AND b3.product_id = a.B_prod
        )

        -- 插入当月数据
        INSERT INTO dbo.Earned_Contributions (
            Month_Year, membership_id, cover_state, cover_type,
            H_prod, A_prod, B_prod,
            earned_contributions, bonus_amount,
            H_earned, A_earned, B_earned,
            H_bonus, A_bonus, B_bonus)
        SELECT
            Month_Year, membership_id, cover_state, cover_type,
            H_prod, A_prod, B_prod,
            earned_contributions, bonus_amount,
            -- H_earned
            CASE WHEN ISNULL(RP_flag, 1) = 0
                 THEN CAST(((curr_H_rate * (1 + overall_lhc - con_discount) * (1 - corporate_discount - overall_agediscount)) / ((curr_H_rate * (1 + overall_lhc - con_discount) + curr_A_rate + curr_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * earned_contributions AS decimal(18,2))
                 ELSE CAST(((prev_H_rate * (1 + overall_lhc - con_discount) * (1 - corporate_discount - overall_agediscount)) / ((prev_H_rate * (1 + overall_lhc - con_discount) + prev_A_rate + prev_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * earned_contributions AS decimal(18,2))
            END,
            -- A_earned
            CASE WHEN ISNULL(RP_flag, 1) = 0
                 THEN CAST(((curr_A_rate * (1 - corporate_discount - overall_agediscount)) / ((curr_H_rate * (1 + overall_lhc - con_discount) + curr_A_rate + curr_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * earned_contributions AS decimal(18,2))
                 ELSE CAST(((prev_A_rate * (1 - corporate_discount - overall_agediscount)) / ((prev_H_rate * (1 + overall_lhc - con_discount) + prev_A_rate + prev_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * earned_contributions AS decimal(18,2))
            END,
            -- B_earned
            CASE WHEN ISNULL(RP_flag, 1) = 0
                 THEN CAST(((curr_B_rate * (1 - corporate_discount - overall_agediscount)) / ((curr_H_rate * (1 + overall_lhc - con_discount) + curr_A_rate + curr_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * earned_contributions AS decimal(18,2))
                 ELSE CAST(((prev_B_rate * (1 - corporate_discount - overall_agediscount)) / ((prev_H_rate * (1 + overall_lhc - con_discount) + prev_A_rate + prev_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * earned_contributions AS decimal(18,2))
            END,
            -- H_bonus
            CASE WHEN ISNULL(RP_flag, 1) = 0
                 THEN CAST(((curr_H_rate * (1 + overall_lhc - con_discount) * (1 - corporate_discount - overall_agediscount)) / ((curr_H_rate * (1 + overall_lhc - con_discount) + curr_A_rate + curr_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * bonus_amount AS decimal(18,2))
                 ELSE CAST(((prev_H_rate * (1 + overall_lhc - con_discount) * (1 - corporate_discount - overall_agediscount)) / ((prev_H_rate * (1 + overall_lhc - con_discount) + prev_A_rate + prev_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * bonus_amount AS decimal(18,2))
            END,
            -- A_bonus
            CASE WHEN ISNULL(RP_flag, 1) = 0
                 THEN CAST(((curr_A_rate * (1 - corporate_discount - overall_agediscount)) / ((curr_H_rate * (1 + overall_lhc - con_discount) + curr_A_rate + curr_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * bonus_amount AS decimal(18,2))
                 ELSE CAST(((prev_A_rate * (1 - corporate_discount - overall_agediscount)) / ((prev_H_rate * (1 + overall_lhc - con_discount) + prev_A_rate + prev_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * bonus_amount AS decimal(18,2))
            END,
            -- B_bonus
            CASE WHEN ISNULL(RP_flag, 1) = 0
                 THEN CAST(((curr_B_rate * (1 - corporate_discount - overall_agediscount)) / ((curr_H_rate * (1 + overall_lhc - con_discount) + curr_A_rate + curr_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * bonus_amount AS decimal(18,2))
                 ELSE CAST(((prev_B_rate * (1 - corporate_discount - overall_agediscount)) / ((prev_H_rate * (1 + overall_lhc - con_discount) + prev_A_rate + prev_B_rate) * (1 - corporate_discount - overall_agediscount) + 0.0001)) * bonus_amount AS decimal(18,2))
            END
        FROM All_Data;

        SET @LoopMonth = DATEADD(MONTH, 1, @LoopMonth);
    END

    DROP TABLE #product_rates;

END;
GO
