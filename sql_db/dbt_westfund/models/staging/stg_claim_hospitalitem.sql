WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'claim_hospitalitem') }}
)

SELECT
    claim_id,
    claim_line_id,
    service_type,
    num_services,
    fee,
    benefit,
    excess,
    num_beddays,
    admission_date,
    discharge_date
FROM source
