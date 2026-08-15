{% snapshot snapshot_store %}

{{
    config(
        target_schema='SILVER',
        unique_key='store_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        st.value AS store_json,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('bronze_store') }},
         LATERAL FLATTEN(
             input => RAW_DATA:stores_data
         ) st

),

prepared AS (

    SELECT

        -------------------------------------------------
        -- Store ID
        -------------------------------------------------

        TRIM(
            store_json:store_id::STRING
        ) AS store_id,

        -------------------------------------------------
        -- Last Modified Date
        -------------------------------------------------

        COALESCE(

            TRY_TO_TIMESTAMP_NTZ(
                store_json:last_modified_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_TIMESTAMP_NTZ(
                store_json:last_modified_date::STRING
            )

        ) AS last_modified_date,

        -------------------------------------------------
        -- Complete Store JSON
        -------------------------------------------------

        store_json AS raw_data,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped

)

SELECT *

FROM prepared

WHERE store_id IS NOT NULL
  AND store_id <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY store_id

    ORDER BY
        last_modified_date DESC NULLS LAST,
        LOADED_AT DESC

) = 1

{% endsnapshot %}