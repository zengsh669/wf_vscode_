WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'claim_generalitem') }}
)

SELECT
    claim_id,
    claim_line_id,
    service_type,
    num_services,
    fee,
    benefit,
    excess
FROM source
