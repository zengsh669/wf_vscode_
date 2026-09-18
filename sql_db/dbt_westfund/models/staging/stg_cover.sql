WITH source AS (
    SELECT *
    FROM {{ source('bronze', 'cover') }}
)

SELECT
    membership_id,
    cover_version,
    cover_type,
    cover_state,
    cover_from_date,
    termination_date,
    description
FROM source
