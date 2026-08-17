{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *

    FROM {{ ref('silver_campaign') }}

),

final AS (

    SELECT
        /* Surrogate Key */
       {{ dbt_utils.generate_surrogate_key(['campaign_id']) }} AS campaign_key,
 
        /* Natural Key */
        campaign_id,

        -------------------------------------------------
        -- Campaign Details
        -------------------------------------------------

        campaign_name,

        campaign_type,

        channel,

        description,



        start_date,

        end_date,

        last_modified_date,



        target_audience,

        audience_group,

        audience_age_band,

        audience_location,

        demographic_segment,



        campaign_duration_days,



        budget,

        total_cost,

        total_revenue,



        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src

    WHERE campaign_id IS NOT NULL

      AND TRIM(campaign_id) <> ''

)

SELECT *

FROM final