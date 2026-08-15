{% snapshot snapshot_campaign %}

{{
    config(
        target_schema='SILVER',
        unique_key='campaign_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        campaign.value AS campaign_json,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('bronze_campaign') }},
         LATERAL FLATTEN(
             input => RAW_DATA:campaigns_data
         ) campaign

),

prepared AS (

    SELECT

        -------------------------------------------------
        -- Campaign ID
        -------------------------------------------------

        TRIM(
            campaign_json:campaign_id::STRING
        ) AS campaign_id,

        -------------------------------------------------
        -- Last Modified Date
        -------------------------------------------------

        COALESCE(

            TRY_TO_TIMESTAMP_NTZ(
                campaign_json:last_modified_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_TIMESTAMP_NTZ(
                campaign_json:last_modified_date::STRING
            )

        ) AS last_modified_date,

        -------------------------------------------------
        -- Complete Campaign JSON
        -------------------------------------------------

        campaign_json AS raw_data,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped

)

SELECT *

FROM prepared

WHERE campaign_id IS NOT NULL
  AND campaign_id <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY campaign_id

    ORDER BY
        last_modified_date DESC NULLS LAST,
        LOADED_AT DESC

) = 1

{% endsnapshot %}