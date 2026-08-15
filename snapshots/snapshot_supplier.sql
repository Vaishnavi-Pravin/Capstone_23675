{% snapshot snapshot_supplier %}

{{
    config(
        target_schema='SILVER',
        unique_key='supplier_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT

        supplier.value AS supplier_json,

        LOADED_AT,

        SOURCE_FILE,

        BATCH_ID

    FROM {{ ref('bronze_supplier') }},

         LATERAL FLATTEN(
             INPUT => RAW_DATA:suppliers_data
         ) supplier

),

prepared AS (

    SELECT

        -------------------------------------------------
        -- Natural Key
        -------------------------------------------------

        TRIM(
            supplier_json:supplier_id::STRING
        ) AS supplier_id,

        -------------------------------------------------
        -- Last Modified Date
        -------------------------------------------------

        TRY_TO_TIMESTAMP_NTZ(
            supplier_json:last_modified_date::STRING
        ) AS last_modified_date,

        -------------------------------------------------
        -- Complete Supplier JSON
        -------------------------------------------------

        supplier_json AS raw_data,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        LOADED_AT,

        SOURCE_FILE,

        BATCH_ID

    FROM unwrapped

)

SELECT *

FROM prepared

WHERE supplier_id IS NOT NULL

  AND TRIM(supplier_id) <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY supplier_id

    ORDER BY
        last_modified_date DESC NULLS LAST,
        LOADED_AT DESC

) = 1

{% endsnapshot %}