WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'claim_line') }}
)

SELECT
    claim_id,
    claim_line_id,
    provider_number_id,
    episode_id,
    claim_type,
    membership_id,
    person_id,
    service_date,
    claim_line_status_type,
    status_date,
    product_id
FROM source
