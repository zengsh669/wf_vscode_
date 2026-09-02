

DECLARE @CurrentMonthStart DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);

WITH SalesChannelMappingExcel (Sales_Channel, Grp) AS (
    SELECT * FROM (VALUES
        ('Phone', 'Phone'),
        ('Internet', 'Web'),
        ('Face to Face', 'Face to Face'),
        ('Paper', 'Face to Face'),
        ('John Small', 'Previous Aggregator'),
        ('Choosi', 'Previous Aggregator'),
        ('Corporate Group', 'Corporate'),
        ('Tax Agent', 'Phone'),
        ('Shaft Magazine', 'Phone'),
        ('Sept/Oct Upgrade Promo 2012', 'Phone'),
        ('Internet - Overseas', 'Web'),
        ('Overseas Welcome Centre', 'Phone'),
        ('Field Days', 'Face to Face'),
        ('Sunshine Coast Regional Council', 'Corporate'),
        ('Woman''s Lifestyle Expo', 'Face to Face'),
        ('Rockhampton Regional Council', 'Corporate'),
        ('Compare Health', 'Previous Aggregator'),
        ('Compare the Market', 'Compare the Market'),
        ('IRC Isacc Regional Council', 'Corporate'),
        ('MDSS Moranbah District Support Ser', 'Corporate'),
        ('Live FM', 'Face to Face'),
        ('Ag Force', 'Face to Face'),
        ('Covad', 'Previous Aggregator'),
        ('Australian Menopause Centre', 'Face to Face'),
        ('Family Health Guide', 'Face to Face'),
        ('Shopping Centre', 'Face to Face'),
        ('Canstar', 'Previous Aggregator'),
        ('Agforce North', 'Face to Face'),
        ('Agforce Central', 'Face to Face'),
        ('Agforce East', 'Face to Face'),
        ('Agforce South', 'Face to Face'),
        ('Agforce West', 'Face to Face'),
        ('Union Shopper', 'Face to Face'),
        ('Member Plus', 'Face to Face'),
        ('YourShare', 'Phone'),
        ('F2F-External activity', 'Face to Face'),
        ('F2F-Care Centre Walk-in', 'Face to Face'),
        ('Web Assist', 'Phone'),
        ('JCU Dental Cairns', 'No Channel Group'),
        ('Branch Direct Phone', 'Face to Face'),
        ('Corporate F2F', 'Corporate'),
        ('No Channel', 'No Channel Group'),
        ('Web', 'Web'),
        ('Health Deal', 'Health Deal'),
        ('Other', 'Other'),
        ('Compare Club', 'Compare Club'),
        ('Finder', 'Finder')
    ) AS x(Sales_Channel, Grp)
),
HistoricalMovement AS (
    SELECT
        gk.[Run Month]                                       AS MonthYear,
        gk.[Membership Number]                              AS Membership_ID,
        CASE gk.[Membership Status] WHEN 'J' THEN 'Join'
                                     WHEN 'T' THEN 'Termination'
                                     ELSE NULL END            AS Movement_Type,
        gk.[Sales Channel]                                   AS Sales_Channel,
        gk.Agent                                             AS Agent,
        CASE
            WHEN gk.Agent IN (
                'No Agency','No Agent','CTM','Web Join','Compare Health','Choosi',
                'Biloela Agency','Blackwater Agency','Blackwater','Covad','Dysart Agency',
                'Forbes Agency','John Small Brokerage','Kalgoorlie Agency','Katoomba Agency',
                'Moura Agency - First National','Rylstone Agency','Sarina Agency',
                'Telephone Sales','Union Shopper','Wellington Agency','YourShare','HICA Agency'
            )
            OR gk.Agent LIKE '%Parkes Agency%'
            THEN COALESCE(scm.Grp, 'No Channel Group')
            ELSE 'Corporate'
        END                                                  AS Sales_Channel_Group
    FROM SILVER.dbo.Membership_Group_Key gk
    LEFT JOIN SalesChannelMappingExcel scm
        ON LTRIM(RTRIM(gk.[Sales Channel])) = LTRIM(RTRIM(scm.Sales_Channel))
    WHERE gk.[Membership Status] IN ('J', 'T')
      AND gk.[Run Month] < @CurrentMonthStart
      AND gk.[Product Code] NOT IN ('OSC', 'NZO', 'FCO')
      AND gk.[Product Code] NOT IN ('AMB', 'AMBU')
      AND NOT EXISTS (
          SELECT 1
          FROM BRONZE.dbo.group_key_full_by_branch b
          WHERE b.membership_id = gk.[Membership Number]
            AND b.hosp_product_id IN (191, 192, 193, 194, 195, 196)
            AND b.extras_product_id IS NULL
      )
),
CurrentMonthAmbulance AS (
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
CurrentMonthMovement AS (
    SELECT
        @CurrentMonthStart                                 AS MonthYear,
        m.membership_id                                    AS Membership_ID,
        'Join'                                              AS Movement_Type,
        ma.description                                     AS Agent
    FROM BRONZE.dbo.memship m
    LEFT JOIN BRONZE.dbo.MemberAgent ma
        ON ma.membership_id = m.membership_id
    WHERE m.effective_join_date >= @CurrentMonthStart
      AND m.effective_join_date < DATEADD(MONTH, 1, @CurrentMonthStart)
      AND m.memship_status = 'A'
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthAmbulance amb WHERE amb.membership_id = m.membership_id)
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthOVHC ovhc WHERE ovhc.membership_id = m.membership_id)

    UNION ALL

    SELECT
        @CurrentMonthStart                                 AS MonthYear,
        m.membership_id                                    AS Membership_ID,
        'Termination'                                       AS Movement_Type,
        ma.description                                     AS Agent
    FROM BRONZE.dbo.memship m
    LEFT JOIN BRONZE.dbo.MemberAgent ma
        ON ma.membership_id = m.membership_id
    WHERE m.effective_termination_date >= @CurrentMonthStart
      AND m.effective_termination_date < DATEADD(MONTH, 1, @CurrentMonthStart)
      AND m.memship_status = 'T'
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthAmbulance amb WHERE amb.membership_id = m.membership_id)
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthOVHC ovhc WHERE ovhc.membership_id = m.membership_id)
),
AllMovement AS (
    SELECT MonthYear, Membership_ID, Movement_Type, Sales_Channel, Agent, Sales_Channel_Group
    FROM HistoricalMovement

    UNION ALL

    SELECT
        cm.MonthYear,
        cm.Membership_ID,
        cm.Movement_Type,
        lpscbp.Sales_Channel_Description                  AS Sales_Channel,
        cm.Agent,
        CASE
            WHEN cm.Agent IN (
                'No Agency','No Agent','CTM','Web Join','Compare Health','Choosi',
                'Biloela Agency','Blackwater Agency','Blackwater','Covad','Dysart Agency',
                'Forbes Agency','John Small Brokerage','Kalgoorlie Agency','Katoomba Agency',
                'Moura Agency - First National','Rylstone Agency','Sarina Agency',
                'Telephone Sales','Union Shopper','Wellington Agency','YourShare','HICA Agency'
            )
            OR cm.Agent LIKE '%Parkes Agency%'
            THEN COALESCE(scme.Grp, 'No Channel Group')
            ELSE 'Corporate'
        END                                                 AS Sales_Channel_Group
    FROM CurrentMonthMovement cm
    LEFT JOIN SILVER.dbo.Latest_Promo_Sales_Channel_By_Person lpscbp
        ON lpscbp.Membership_Id = cm.Membership_ID
        AND lpscbp.Relationship = 1
    LEFT JOIN SalesChannelMappingExcel scme
        ON LTRIM(RTRIM(lpscbp.Sales_Channel_Description)) = LTRIM(RTRIM(scme.Sales_Channel))
)
-- Detail output: one row per Join/Termination record, all breakdown fields from both
-- Query 1 (Sales_Channel_Group) and Query 2 (Operator) included, no aggregation.
SELECT
    am.MonthYear,
    am.Membership_ID,
    am.Movement_Type,
    am.Agent,
    am.Sales_Channel,
    am.Sales_Channel_Group,
    lpscbp.First_Name + ' ' + lpscbp.Surname   AS Operator
FROM AllMovement am
LEFT JOIN SILVER.dbo.Latest_Promo_Sales_Channel_By_Person lpscbp
    ON lpscbp.Membership_Id = am.Membership_ID
    AND lpscbp.Relationship = 1
ORDER BY am.MonthYear, am.Sales_Channel_Group, Operator, am.Membership_ID;
