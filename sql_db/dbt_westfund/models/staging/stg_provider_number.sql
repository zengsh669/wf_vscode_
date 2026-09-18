WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'provider_number') }}
)

SELECT
    provider_number_id,
    provider_id
FROM source
