WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'provider') }}
)

SELECT
    provider_id,
    provider_type
FROM source
