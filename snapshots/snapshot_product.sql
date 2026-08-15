{% snapshot snapshot_product %}

{{
    config(
        target_schema='SILVER',
        unique_key='product_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        prod.value AS product_json,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('bronze_product') }},
         LATERAL FLATTEN(
             input => RAW_DATA:products_data
         ) prod

),

prepared AS (

    SELECT

        -------------------------------------------------
        -- Product ID
        -------------------------------------------------

        TRIM(
            product_json:product_id::STRING
        ) AS product_id,

        -------------------------------------------------
        -- Last Modified Date
        -------------------------------------------------

        COALESCE(

            TRY_TO_TIMESTAMP_NTZ(
                product_json:last_modified_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_TIMESTAMP_NTZ(
                product_json:last_modified_date::STRING
            )

        ) AS last_modified_date,

        -------------------------------------------------
        -- Complete Product JSON
        -------------------------------------------------

        product_json AS raw_data,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped

)

SELECT *

FROM prepared

WHERE product_id IS NOT NULL
  AND product_id <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY product_id

    ORDER BY
        last_modified_date DESC NULLS LAST,
        LOADED_AT DESC

) = 1

{% endsnapshot %}