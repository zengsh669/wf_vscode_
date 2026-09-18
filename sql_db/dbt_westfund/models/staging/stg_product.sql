WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'product') }}
)

SELECT
    product_id,
    product_type,
    product_code
FROM source
