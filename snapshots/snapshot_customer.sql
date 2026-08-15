{% snapshot snapshot_customer %}

{{
    config(
        target_schema='SILVER',
        unique_key='customer_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        cust.value AS customer_json,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('bronze_customer') }},
         LATERAL FLATTEN(
             input => RAW_DATA:customers_data
         ) cust

),

prepared AS (

    SELECT

        -------------------------------------------------
        -- Customer ID
        -------------------------------------------------

        TRIM(
            customer_json:customer_id::STRING
        ) AS customer_id,

        -------------------------------------------------
        -- Last Modified Date
        -------------------------------------------------

        COALESCE(

            TRY_TO_TIMESTAMP_NTZ(
                customer_json:last_modified_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_TIMESTAMP_NTZ(
                customer_json:last_modified_date::STRING
            )

        ) AS last_modified_date,

        -------------------------------------------------
        -- Complete Raw Customer JSON
        -------------------------------------------------

        customer_json AS raw_data,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped

)

SELECT *

FROM prepared

WHERE customer_id IS NOT NULL
  AND customer_id <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY customer_id

    ORDER BY
        last_modified_date DESC NULLS LAST,
        LOADED_AT DESC

) = 1

{% endsnapshot %}