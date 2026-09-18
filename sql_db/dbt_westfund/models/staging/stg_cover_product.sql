WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'cover_product') }}
)

SELECT
    membership_id,
    cover_version,
    product_id
FROM source
