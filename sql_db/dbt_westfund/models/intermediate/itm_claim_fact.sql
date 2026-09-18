{% set start_date = var('start_date', '2023-07-01') %}
{% set end_date = var('end_date', '2026-08-31') %}

WITH all_claims AS (

    -- Ambulatory and Medical claims
    SELECT
        a.claim_id,
        a.claim_line_id,
        a.provider_number_id,
        a.episode_id,
        a.claim_type,
        a.membership_id,
        a.person_id,
        a.service_date,
        a.claim_line_status_type,
        a.status_date,
        a.product_id AS amb_id,
        b.service_type,
        b.num_services,
        b.fee,
        b.benefit,
        b.excess,
        0 AS bed_days,
        'NA' AS stay_type,
        CASE WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 0 AND 54 THEN '00-54'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 55 AND 59 THEN '55-59'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 60 AND 64 THEN '60-64'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 65 AND 69 THEN '65-69'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 70 AND 74 THEN '70-74'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 75 AND 79 THEN '75-79'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 80 AND 84 THEN '80-84'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) >= 85 THEN '85+'
        ELSE 'NA' END AS age_group
    FROM {{ ref('stg_claim_line') }} a
    LEFT JOIN {{ ref('stg_claim_generalitem') }} b
        ON a.claim_id = b.claim_id
       AND a.claim_line_id = b.claim_line_id
    LEFT JOIN {{ ref('stg_person') }} p
        ON a.person_id = p.person_id
    WHERE a.status_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
      AND a.claim_type IN ('A','B','M')
      AND a.claim_line_status_type = 'P'

    UNION ALL

    -- Hospital claims
    SELECT
        a.claim_id,
        a.claim_line_id,
        a.provider_number_id,
        a.episode_id,
        a.claim_type,
        a.membership_id,
        a.person_id,
        a.service_date,
        a.claim_line_status_type,
        a.status_date,
        a.product_id AS amb_id,
        b.service_type,
        b.num_services,
        b.fee,
        b.benefit,
        b.excess,
        b.num_beddays,
        CASE
            WHEN b.admission_date = b.discharge_date THEN 'SD'
            ELSE 'OV'
        END AS stay_type,
        CASE WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 0 AND 54 THEN '00-54'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 55 AND 59 THEN '55-59'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 60 AND 64 THEN '60-64'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 65 AND 69 THEN '65-69'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 70 AND 74 THEN '70-74'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 75 AND 79 THEN '75-79'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) BETWEEN 80 AND 84 THEN '80-84'
             WHEN (DATEDIFF(year, p.date_of_birth, a.service_date) - CASE WHEN a.service_date < DATEADD(year, DATEDIFF(year, p.date_of_birth, a.service_date), p.date_of_birth) THEN 1 ELSE 0 END) >= 85 THEN '85+'
        ELSE 'NA' END AS age_group
    FROM {{ ref('stg_claim_line') }} a
    LEFT JOIN {{ ref('stg_claim_hospitalitem') }} b
        ON a.claim_id = b.claim_id
       AND a.claim_line_id = b.claim_line_id
    LEFT JOIN {{ ref('stg_person') }} p
        ON a.person_id = p.person_id
    WHERE a.status_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
      AND a.claim_type = 'H'
      AND a.claim_line_status_type = 'P'

),

member_details AS (
    SELECT
        cp.membership_id,
        cp.cover_version,
        cp.product_id,
        p.product_type,
        p.product_code,
        c.cover_type,
        c.cover_state,
        c.cover_from_date,
        c.termination_date,
        c.description
    FROM {{ ref('stg_cover_product') }} cp
    LEFT JOIN {{ ref('stg_product') }} p
        ON cp.product_id = p.product_id
    LEFT JOIN {{ ref('stg_cover') }} c
        ON c.membership_id = cp.membership_id
       AND c.cover_version = cp.cover_version
),

provider_details AS (
    SELECT
        pn.provider_number_id,
        pn.provider_id,
        pt.provider_type
    FROM {{ ref('stg_provider_number') }} pn
    LEFT JOIN {{ ref('stg_provider') }} pt
        ON pn.provider_id = pt.provider_id
),

combined_data AS (

    -- Hospital & Medical claims
    SELECT
        ac.claim_id,
        ac.claim_type,
        ac.membership_id,
        ac.person_id,
        ac.service_date,
        ac.status_date,
        ac.service_type,
        ac.stay_type,
        SUM(ac.num_services) AS serv,
        SUM(ac.fee) AS fee_amt,
        SUM(ac.benefit) AS benefit_amt,
        SUM(ac.excess) AS excess_amt,
        SUM(ac.bed_days) AS bed_days,
        md.cover_type,
        md.cover_state,
        ISNULL(md.product_id, 0) AS product_id,
        ac.provider_number_id,
        pt.provider_type,
        ac.age_group,
        SUM(CASE WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '00-54' THEN 0
                 WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '55-59' THEN 0.15 * ac.benefit
                 WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '60-64' THEN 0.425 * ac.benefit
                 WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '65-69' THEN 0.60 * ac.benefit
                 WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '70-74' THEN 0.70 * ac.benefit
                 WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '75-79' THEN 0.76 * ac.benefit
                 WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '80-84' THEN 0.78 * ac.benefit
                 WHEN ISNULL(md.product_id,0) NOT IN (10,34,65,191,192,193,194,195,196) AND ac.age_group = '85+' THEN 0.82 * ac.benefit
            ELSE 0 END) AS gross_deficit
    FROM all_claims ac
    LEFT JOIN provider_details pt
        ON ac.provider_number_id = pt.provider_number_id
    LEFT JOIN member_details md
        ON ac.membership_id = md.membership_id
    WHERE ac.claim_type IN ('H', 'M')
      AND md.product_type = 'H'
      AND md.cover_version = (
          SELECT MAX(cover_version)
          FROM member_details
          WHERE cover_from_date <= ac.service_date
            AND membership_id = ac.membership_id
      )
    GROUP BY
        ac.claim_id, ac.claim_type, ac.membership_id, ac.person_id,
        ac.service_date, ac.status_date, ac.service_type, ac.stay_type,
        md.cover_type, md.cover_state, md.product_id,
        ac.provider_number_id, pt.provider_type, ac.age_group

    UNION ALL

    -- Ambulatory claims
    SELECT
        ac.claim_id,
        ac.claim_type,
        ac.membership_id,
        ac.person_id,
        ac.service_date,
        ac.status_date,
        ac.service_type,
        ac.stay_type,
        SUM(ac.num_services) AS serv,
        SUM(ac.fee) AS fee_amt,
        SUM(ac.benefit) AS benefit_amt,
        SUM(ac.excess) AS excess_amt,
        SUM(ac.bed_days) AS bed_days,
        md.cover_type,
        md.cover_state,
        ISNULL(md.product_id, 0) AS product_id,
        ac.provider_number_id,
        pt.provider_type,
        ac.age_group,
        0 AS gross_deficit
    FROM all_claims ac
    LEFT JOIN provider_details pt
        ON ac.provider_number_id = pt.provider_number_id
    LEFT JOIN member_details md
        ON ac.membership_id = md.membership_id
    WHERE ac.claim_type = 'A'
      AND md.product_type = 'A'
      AND md.cover_version = (
          SELECT MAX(cover_version)
          FROM member_details
          WHERE cover_from_date <= ac.service_date
            AND membership_id = ac.membership_id
      )
    GROUP BY
        ac.claim_id, ac.claim_type, ac.membership_id, ac.person_id,
        ac.service_date, ac.status_date, ac.service_type, ac.stay_type,
        md.cover_type, md.cover_state, md.product_id,
        ac.provider_number_id, pt.provider_type, ac.age_group

    UNION ALL

    -- B claims
    SELECT
        ac.claim_id,
        ac.claim_type,
        ac.membership_id,
        ac.person_id,
        ac.service_date,
        ac.status_date,
        ac.service_type,
        ac.stay_type,
        SUM(ac.num_services) AS serv,
        SUM(ac.fee) AS fee_amt,
        SUM(ac.benefit) AS benefit_amt,
        SUM(ac.excess) AS excess_amt,
        SUM(ac.bed_days) AS bed_days,
        md.cover_type,
        md.cover_state,
        ISNULL(md.product_id, 0) AS product_id,
        ac.provider_number_id,
        pt.provider_type,
        ac.age_group,
        0 AS gross_deficit
    FROM all_claims ac
    LEFT JOIN provider_details pt
        ON ac.provider_number_id = pt.provider_number_id
    LEFT JOIN member_details md
        ON ac.membership_id = md.membership_id
       AND ac.amb_id = md.product_id
    WHERE ac.claim_type = 'B'
      AND md.cover_version = (
          SELECT MAX(cover_version)
          FROM member_details
          WHERE cover_from_date <= ac.service_date
            AND membership_id = ac.membership_id
      )
    GROUP BY
        ac.claim_id, ac.claim_type, ac.membership_id, ac.person_id,
        ac.service_date, ac.status_date, ac.service_type, ac.stay_type,
        md.cover_type, md.cover_state, md.product_id,
        ac.provider_number_id, pt.provider_type, ac.age_group

)

SELECT *
FROM combined_data
WHERE service_date >= '{{ start_date }}'
  AND benefit_amt <> 0
  AND claim_type IN ('A','B','M','H')
