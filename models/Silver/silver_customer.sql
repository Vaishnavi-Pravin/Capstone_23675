{{ config(materialized='table', schema ='SILVER') }}

WITH src_customer AS (

    SELECT *

    FROM {{ ref('snapshot_customer') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT



        customer_id,



        INITCAP(
            TRIM(raw_data:first_name::STRING)
        ) AS first_name,

        INITCAP(
            TRIM(raw_data:last_name::STRING)
        ) AS last_name,



        CONCAT_WS(
            ' ',
            NULLIF(
                INITCAP(TRIM(raw_data:first_name::STRING)),
                ''
            ),
            NULLIF(
                INITCAP(TRIM(raw_data:last_name::STRING)),
                ''
            )
        ) AS full_name,



        LOWER(
            TRIM(raw_data:email::STRING)
        ) AS email,



        CASE

            WHEN raw_data:email IS NULL
                THEN FALSE

            WHEN REGEXP_LIKE(
                TRIM(raw_data:email::STRING),
                '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
            )
                THEN TRUE

            ELSE FALSE

        END AS is_valid_email,



        REGEXP_REPLACE(
            TRIM(raw_data:phone::STRING),
            '[^0-9]',
            ''
        ) AS phone_number,



        CASE

            WHEN raw_data:phone IS NULL
                THEN FALSE

            WHEN REGEXP_LIKE(
                TRIM(raw_data:phone::STRING),
                '^\+?[0-9][0-9 ()\.-]*[0-9]$'
            )
            AND LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_data:phone::STRING),
                    '[^0-9]',
                    ''
                )
            ) BETWEEN 10 AND 15
                THEN TRUE

            ELSE FALSE

        END AS is_valid_phone,



        COALESCE(

            TRY_TO_DATE(
                TRIM(raw_data:birth_date::STRING),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:birth_date::STRING),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:birth_date::STRING),
                'MM/DD/YYYY'
            )

        ) AS birth_date,



        COALESCE(

            TRY_TO_DATE(
                TRIM(raw_data:registration_date::STRING),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:registration_date::STRING),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:registration_date::STRING),
                'MM/DD/YYYY'
            )

        ) AS registration_date,



        COALESCE(

            TRY_TO_DATE(
                TRIM(raw_data:last_purchase_date::STRING),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:last_purchase_date::STRING),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:last_purchase_date::STRING),
                'MM/DD/YYYY'
            )

        ) AS last_purchase_date,



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



        INITCAP(
            TRIM(raw_data:address:street::STRING)
        ) AS street,

        INITCAP(
            TRIM(raw_data:address:city::STRING)
        ) AS city,

        UPPER(
            TRIM(raw_data:address:state::STRING)
        ) AS state,

        UPPER(
            TRIM(raw_data:address:country::STRING)
        ) AS country,

        TRIM(
            raw_data:address:zip_code::STRING
        ) AS zip_code,



        CONCAT_WS(
            ', ',
            NULLIF(
                INITCAP(
                    TRIM(raw_data:address:street::STRING)
                ),
                ''
            ),

            NULLIF(
                INITCAP(
                    TRIM(raw_data:address:city::STRING)
                ),
                ''
            ),

            NULLIF(
                UPPER(
                    TRIM(raw_data:address:state::STRING)
                ),
                ''
            ),

            NULLIF(
                UPPER(
                    TRIM(raw_data:address:country::STRING)
                ),
                ''
            ),

            NULLIF(
                TRIM(
                    raw_data:address:zip_code::STRING
                ),
                ''
            )

        ) AS full_address,



        INITCAP(
            TRIM(raw_data:occupation::STRING)
        ) AS occupation,

        INITCAP(
            TRIM(raw_data:income_bracket::STRING)
        ) AS income_bracket,

        INITCAP(
            TRIM(raw_data:loyalty_tier::STRING)
        ) AS loyalty_tier,

        INITCAP(
            TRIM(raw_data:preferred_communication::STRING)
        ) AS preferred_communication,

        INITCAP(
            TRIM(raw_data:preferred_payment_method::STRING)
        ) AS preferred_payment_method,

        raw_data:marketing_opt_in::BOOLEAN AS marketing_opt_in,

        TRY_TO_NUMBER(
            raw_data:total_purchases::STRING
        ) AS total_purchases,

        TRY_TO_DECIMAL(
            raw_data:total_spend::STRING,
            18,
            2
        ) AS total_spend,



        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src_customer

),

with_age AS (

    SELECT

        *,



        CASE

            WHEN birth_date IS NULL
                THEN NULL

            ELSE
                DATEDIFF(
                    YEAR,
                    birth_date,
                    CURRENT_DATE()
                )
                -
                CASE

                    WHEN DATE_FROM_PARTS(
                        YEAR(CURRENT_DATE()),
                        MONTH(birth_date),
                        DAY(birth_date)
                    ) > CURRENT_DATE()

                    THEN 1

                    ELSE 0

                END

        END AS age

    FROM cleaned

),

final AS (

    SELECT

        *,



        CASE

            WHEN age BETWEEN 18 AND 35
                THEN 'Young'

            WHEN age BETWEEN 36 AND 55
                THEN 'Middle-aged'

            WHEN age >= 56
                THEN 'Senior'

            ELSE NULL

        END AS customer_segment

    FROM with_age

)

SELECT *

FROM final