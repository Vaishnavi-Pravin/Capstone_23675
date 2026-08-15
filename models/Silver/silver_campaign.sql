{{ config(materialized='table', schema ='SILVER') }}

WITH src_campaign AS (

    SELECT *

    FROM {{ ref('snapshot_campaign') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        -------------------------------------------------
        -- Keys
        -------------------------------------------------

        campaign_id,

        -------------------------------------------------
        -- Campaign Details
        -------------------------------------------------

        INITCAP(
            TRIM(raw_data:campaign_name::STRING)
        ) AS campaign_name,

        INITCAP(
            TRIM(raw_data:campaign_type::STRING)
        ) AS campaign_type,

        INITCAP(
            TRIM(raw_data:channel::STRING)
        ) AS channel,

        TRIM(
            raw_data:description::STRING
        ) AS description,

        -------------------------------------------------
        -- Campaign Dates
        -------------------------------------------------

        TRY_TO_TIMESTAMP_NTZ(
            TRIM(raw_data:start_date::STRING)
        ) AS start_date,

        TRY_TO_TIMESTAMP_NTZ(
            TRIM(raw_data:end_date::STRING)
        ) AS end_date,

        COALESCE(

            TRY_TO_DATE(
                TRIM(raw_data:last_modified_date::STRING),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:last_modified_date::STRING),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:last_modified_date::STRING),
                'MM/DD/YYYY'
            )

        ) AS last_modified_date,

        -------------------------------------------------
        -- Currency Fields
        --
        -- Source examples:
        -- "$24,005.75"
        -- "$12,210.23"
        -------------------------------------------------

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(raw_data:budget::STRING),
                '[^0-9.-]',
                ''
            ),
            18,
            2
        ) AS budget,

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(raw_data:total_cost::STRING),
                '[^0-9.-]',
                ''
            ),
            18,
            2
        ) AS total_cost,

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(raw_data:total_revenue::STRING),
                '[^0-9.-]',
                ''
            ),
            18,
            2
        ) AS total_revenue,

        -------------------------------------------------
        -- Target Audience
        -------------------------------------------------

        TRIM(
            raw_data:target_audience::STRING
        ) AS target_audience,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src_campaign

),

demographics AS (

    SELECT

        *,

        -------------------------------------------------
        -- Audience Demographic
        --
        -- Examples:
        -- Students
        -- Families
        -- Professionals
        -- Seniors
        -------------------------------------------------

        TRIM(
            SPLIT_PART(
                target_audience,
                ',',
                1
            )
        ) AS audience_group,

        -------------------------------------------------
        -- Age Band
        --
        -- Examples:
        -- 18-25
        -- 25-50
        -- 30-50
        -- 60+
        -------------------------------------------------

        TRIM(
            SPLIT_PART(
                target_audience,
                ',',
                2
            )
        ) AS audience_age_band,

        -------------------------------------------------
        -- Geographic / Location Segment
        --
        -- Examples:
        -- Campus
        -- Suburban
        -- Urban
        -- All Areas
        -------------------------------------------------

        TRIM(
            SPLIT_PART(
                target_audience,
                ',',
                3
            )
        ) AS audience_location

    FROM cleaned

),

final AS (

    SELECT

        -------------------------------------------------
        -- Campaign
        -------------------------------------------------

        campaign_id,

        campaign_name,

        campaign_type,

        channel,

        description,

        -------------------------------------------------
        -- Dates
        -------------------------------------------------

        start_date,

        end_date,

        last_modified_date,

        -------------------------------------------------
        -- Campaign Duration
        --
        -- Number of calendar days between start and end.
        -------------------------------------------------

        CASE

            WHEN start_date IS NOT NULL
             AND end_date IS NOT NULL
             AND end_date >= start_date

            THEN DATEDIFF(
                DAY,
                start_date,
                end_date
            )

            ELSE NULL

        END AS campaign_duration_days,

        -------------------------------------------------
        -- Financials
        --
        -- All normalized to numeric USD values.
        -------------------------------------------------

        budget,

        total_cost,

        total_revenue,

        -------------------------------------------------
        -- Demographics
        -------------------------------------------------

        target_audience,

        INITCAP(
            audience_group
        ) AS audience_group,

        audience_age_band,

        INITCAP(
            audience_location
        ) AS audience_location,

        -------------------------------------------------
        -- Combined Demographic Segment
        --
        -- Example:
        -- Students | 18-25 | Campus
        -------------------------------------------------

        CONCAT_WS(
            ' | ',
            NULLIF(
                INITCAP(audience_group),
                ''
            ),
            NULLIF(
                audience_age_band,
                ''
            ),
            NULLIF(
                INITCAP(audience_location),
                ''
            )
        ) AS demographic_segment,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM demographics

)

SELECT *

FROM final