DECLARE @WindowStart DATE = DATEADD(DAY, -30, CAST(GETDATE() AS DATE));
DECLARE @WindowEnd   DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE));  -- exclusive upper bound, includes today

WITH CurrentMonthAmbulance AS (
    SELECT DISTINCT co.membership_id
    FROM BRONZE.dbo.cover co
    JOIN BRONZE.dbo.cover_product cp
        ON co.membership_id = cp.membership_id
        AND co.cover_version = cp.cover_version
    JOIN BRONZE.dbo.product pr
        ON cp.product_id = pr.product_id
        AND pr.product_type = 'B'
    WHERE co.status_flag = 'A'
      AND co.cover_version = (
          SELECT MAX(co2.cover_version)
          FROM BRONZE.dbo.cover co2
          WHERE co2.membership_id = co.membership_id
      )
),
CurrentMonthOVHC AS (
    SELECT DISTINCT co.membership_id
    FROM BRONZE.dbo.cover co
    JOIN BRONZE.dbo.cover_product cp_h
        ON co.membership_id = cp_h.membership_id
        AND co.cover_version = cp_h.cover_version
    JOIN BRONZE.dbo.product pr_h
        ON cp_h.product_id = pr_h.product_id
        AND pr_h.product_type = 'H'
        AND pr_h.product_id IN (191, 192, 193, 194, 195, 196)
    WHERE co.status_flag = 'A'
      AND co.cover_version = (
          SELECT MAX(co2.cover_version)
          FROM BRONZE.dbo.cover co2
          WHERE co2.membership_id = co.membership_id
      )
      AND NOT EXISTS (
          SELECT 1
          FROM BRONZE.dbo.cover_product cp_a
          JOIN BRONZE.dbo.product pr_a
              ON cp_a.product_id = pr_a.product_id
              AND pr_a.product_type = 'A'
          WHERE cp_a.membership_id = co.membership_id
            AND cp_a.cover_version = co.cover_version
      )
),
DailyMovement AS (
    SELECT
        m.effective_join_date                              AS MovementDate,
        m.membership_id                                    AS Membership_ID,
        'Join'                                              AS Movement_Type,
        m.memship_status                                    AS Memship_Status,
        m.termination_code                                  AS Termination_Code,
        m.create_operator                                   AS Create_Operator,
        m.fund_id                                           AS Fund_Id,
        m.state                                             AS State
    FROM BRONZE.dbo.memship m
    WHERE m.effective_join_date >= @WindowStart
      AND m.effective_join_date < @WindowEnd
      AND m.memship_status = 'A'
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthAmbulance amb WHERE amb.membership_id = m.membership_id)
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthOVHC ovhc WHERE ovhc.membership_id = m.membership_id)

    UNION ALL

    SELECT
        m.effective_termination_date                       AS MovementDate,
        m.membership_id                                    AS Membership_ID,
        'Termination'                                       AS Movement_Type,
        m.memship_status                                    AS Memship_Status,
        m.termination_code                                  AS Termination_Code,
        m.create_operator                                   AS Create_Operator,
        m.fund_id                                           AS Fund_Id,
        m.state                                             AS State
    FROM BRONZE.dbo.memship m
    WHERE m.effective_termination_date >= @WindowStart
      AND m.effective_termination_date < @WindowEnd
      AND m.memship_status = 'T'
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthAmbulance amb WHERE amb.membership_id = m.membership_id)
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthOVHC ovhc WHERE ovhc.membership_id = m.membership_id)
)
SELECT
    MovementDate,
    Membership_ID,
    Movement_Type,
    Memship_Status,
    Termination_Code,
    Create_Operator,
    Fund_Id,
    State
FROM DailyMovement
ORDER BY MovementDate, Membership_ID;
