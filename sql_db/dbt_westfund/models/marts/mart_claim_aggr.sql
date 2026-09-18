SELECT
    EOMONTH(service_date, 0) AS service_date,
    EOMONTH(status_date, 0) AS paid_date,
    claim_type,
    service_type,
    'NA' AS stay_type,
    cover_state,
    'NA' AS provider_type,
    SUM(serv) AS serv,
    SUM(fee_amt) AS fee_amt,
    SUM(benefit_amt) AS benefit_amt,
    SUM(gross_deficit) AS gross_deficit,
    product_id
FROM {{ ref('itm_claim_fact') }}
WHERE benefit_amt <> 0
  AND claim_type IN ('A', 'B', 'M')
GROUP BY
    EOMONTH(service_date, 0),
    EOMONTH(status_date, 0),
    claim_type,
    service_type,
    cover_state,
    product_id

UNION ALL

SELECT
    EOMONTH(service_date, 0) AS service_date,
    EOMONTH(status_date, 0) AS paid_date,
    claim_type,
    service_type,
    stay_type,
    cover_state,
    provider_type,
    SUM(serv) AS serv,
    SUM(fee_amt) AS fee_amt,
    SUM(benefit_amt) AS benefit_amt,
    SUM(gross_deficit) AS gross_deficit,
    product_id
FROM {{ ref('itm_claim_fact') }}
WHERE benefit_amt <> 0
  AND claim_type = 'H'
GROUP BY
    EOMONTH(service_date, 0),
    EOMONTH(status_date, 0),
    claim_type,
    service_type,
    stay_type,
    cover_state,
    provider_type,
    product_id
