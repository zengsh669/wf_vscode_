WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'person') }}
)

SELECT
    person_id,
    date_of_birth
FROM source
