/*


Before editing, note:
  - Use Membership_Group_Key.[Run Month] for month filtering/grouping, NOT rundate (offset
    batch timestamp — DESIGN.md > "rundate vs [Run Month] Bug").
  - Latest_Promo_Sales_Channel_By_Person needs WHERE Relationship = 1 added explicitly.
  - Historical OVHC exclusion is a lifetime check, not month-aligned (DESIGN.md > OVHC).
  - Query 2 repeats Query 1's CTEs (WITH scopes to one statement) — keep both in sync.
*/

DECLARE @CurrentMonthStart DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);

WITH SalesChannelMappingExcel (Sales_Channel, Grp) AS (
    /* Sales Channel Mapping.xlsx, 47 rows, confirmed by user as the correct (non-"NEW") file.
       Embedded directly as a VALUES CTE rather than imported as a table — small, static,
       infrequently changed. See DESIGN.md > Sales Channel Group Rebuild. */
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
    /* Historical months from SILVER.dbo.Membership_Group_Key — all available history
       (2021-01 onward), no date floor. Sales Channel Group rebuilt to match Qlik's
       two-step logic: hand-written Agent list (membership_new.md:707-710) decides
       Corporate vs. not; Excel mapping only applies to the "not Corporate" branch. */
    SELECT
        gk.[Run Month]                                       AS MonthYear,
        gk.[Membership Number]                              AS Membership_ID,
        CASE gk.[Membership Status] WHEN 'J' THEN 'Join'
                                     WHEN 'T' THEN 'Termination'
                                     ELSE NULL END            AS Movement_Type,
        gk.[Sales Channel]                                   AS Sales_Channel,
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
      AND gk.[Product Code] NOT IN ('OSC', 'NZO', 'FCO')      -- overseas exclusion, mirrors Group_Key_Load
      AND gk.[Product Code] NOT IN ('AMB', 'AMBU')            -- Ambulance exclusion — confirmed list, see note above
      AND NOT EXISTS (                                        -- OVHC (Overseas Visitor Health Cover) exclusion
          SELECT 1                                            -- pattern taken from GOLD.dbo.Membership_Reporting
          FROM BRONZE.dbo.group_key_full_by_branch b
          WHERE b.membership_id = gk.[Membership Number]
            AND b.hosp_product_id IN (191, 192, 193, 194, 195, 196)
            AND b.extras_product_id IS NULL
      )
),
CurrentMonthAmbulance AS (
    /* Members whose latest cover_version has an Ambulance (product_type = 'B') product
       attached — pattern taken from GOLD.dbo.vw_Membership_Current's LatestCover CTE. */
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
    /* Members whose latest cover_version has a Hospital product in the OVHC ID range
       (191-196) with no Extras product attached — mirrors the historical-side OVHC
       exclusion (group_key_full_by_branch.hosp_product_id + extras_product_id IS NULL),
       but sourced from live cover/cover_product/product since group_key_full_by_branch
       only reflects prior month-end state, not current-month-to-date. */
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
    /* Current month / month-to-date: live query against BRONZE.dbo.memship.
       Sales Channel Group rebuilt using the same two-step logic as historical, sourcing
       Agent from BRONZE.dbo.MemberAgent (confirmed SQL-native equivalent of Qlik's
       Paragon_MemberAgent.qvd — see file header note). */
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
    SELECT MonthYear, Membership_ID, Movement_Type, Sales_Channel, Sales_Channel_Group
    FROM HistoricalMovement

    UNION ALL

    SELECT
        cm.MonthYear,
        cm.Membership_ID,
        cm.Movement_Type,
        lpscbp.Sales_Channel_Description                  AS Sales_Channel,
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

/* ---------------------------------------------------------------------
   Query 1 — mirrors Screenshot 1 (Sales Channel Targets), buildable
   columns only: Sales Channel Group, Joins, Terminations, Net Growth.
   Total Members at Point NOT included here — needs a separate
   point-in-time active-count query, not a movement count.
   --------------------------------------------------------------------- */
SELECT
    Sales_Channel_Group,
    SUM(CASE WHEN Movement_Type = 'Join' THEN 1 ELSE 0 END)         AS Joins,
    SUM(CASE WHEN Movement_Type = 'Termination' THEN 1 ELSE 0 END)  AS Terminations,
    SUM(CASE WHEN Movement_Type = 'Join' THEN 1 ELSE 0 END)
        - SUM(CASE WHEN Movement_Type = 'Termination' THEN 1 ELSE 0 END) AS Net_Growth
FROM AllMovement
GROUP BY Sales_Channel_Group
ORDER BY Sales_Channel_Group;

/* ---------------------------------------------------------------------
   Query 2 — mirrors Screenshot 2 (Joins by Operator), buildable
   columns only: Operator, Joins.

   NOTE: SQL Server scopes a WITH clause to the single statement that
   follows it — Query 1 above consumed the CTEs already, so Query 2 needs
   its own copy of the same WITH chain. Repeated verbatim from the top of
   this file (SalesChannelMappingExcel / HistoricalMovement /
   CurrentMonthAmbulance / CurrentMonthMovement) — the Sales Channel Group
   CASE expression isn't actually needed for this query (Operator doesn't
   depend on it) but the CTE is kept identical to Query 1's for consistency.
   --------------------------------------------------------------------- */
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
                                     ELSE NULL END            AS Movement_Type
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
        'Join'                                              AS Movement_Type
    FROM BRONZE.dbo.memship m
    WHERE m.effective_join_date >= @CurrentMonthStart
      AND m.effective_join_date < DATEADD(MONTH, 1, @CurrentMonthStart)
      AND m.memship_status = 'A'
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthAmbulance amb WHERE amb.membership_id = m.membership_id)
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthOVHC ovhc WHERE ovhc.membership_id = m.membership_id)

    UNION ALL

    SELECT
        @CurrentMonthStart                                 AS MonthYear,
        m.membership_id                                    AS Membership_ID,
        'Termination'                                       AS Movement_Type
    FROM BRONZE.dbo.memship m
    WHERE m.effective_termination_date >= @CurrentMonthStart
      AND m.effective_termination_date < DATEADD(MONTH, 1, @CurrentMonthStart)
      AND m.memship_status = 'T'
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthAmbulance amb WHERE amb.membership_id = m.membership_id)
      AND NOT EXISTS (SELECT 1 FROM CurrentMonthOVHC ovhc WHERE ovhc.membership_id = m.membership_id)
)
SELECT
    Operator,
    SUM(Joins) AS Joins
FROM (
    SELECT
        lpscbp.First_Name + ' ' + lpscbp.Surname                        AS Operator,
        1                                                                AS Joins
    FROM HistoricalMovement hm
    LEFT JOIN SILVER.dbo.Latest_Promo_Sales_Channel_By_Person lpscbp
        ON lpscbp.Membership_Id = hm.Membership_ID
        AND lpscbp.Relationship = 1
    WHERE hm.Movement_Type = 'Join'

    UNION ALL

    SELECT
        lpscbp.First_Name + ' ' + lpscbp.Surname                        AS Operator,
        1                                                                AS Joins
    FROM CurrentMonthMovement cm
    LEFT JOIN SILVER.dbo.Latest_Promo_Sales_Channel_By_Person lpscbp
        ON lpscbp.Membership_Id = cm.Membership_ID
        AND lpscbp.Relationship = 1
    WHERE cm.Movement_Type = 'Join'
) AS OperatorJoins
GROUP BY Operator
ORDER BY Joins DESC;

-- Query 3 (Total Members at Point) removed — see DESIGN.md > "Total Members at Point —
-- REMOVED from current scope" for the user decision and the validated logic to restore if
-- the business confirms this column is needed later.
