{{ config(materialized='table', schema ='SILVER') }}

WITH src AS (

    SELECT *

    FROM {{ ref('snapshot_store') }}

    WHERE dbt_valid_to IS NULL

),

store_clean AS (

    SELECT



        store_id,



        INITCAP(
            TRIM(raw_data:store_name::STRING)
        ) AS store_name,

        INITCAP(
            TRIM(raw_data:store_type::STRING)
        ) AS store_type,

        INITCAP(
            TRIM(raw_data:region::STRING)
        ) AS region,

        TRIM(
            raw_data:manager_id::STRING
        ) AS manager_id,


        COALESCE(

            TRY_TO_DATE(
                TRIM(raw_data:opening_date::STRING),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:opening_date::STRING),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:opening_date::STRING),
                'MM/DD/YYYY'
            )

        ) AS opening_date,

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


        TRY_TO_DECIMAL(
            raw_data:current_sales::STRING,
            18,
            2
        ) AS current_sales,

        TRY_TO_DECIMAL(
            raw_data:sales_target::STRING,
            18,
            2
        ) AS sales_target,

        TRY_TO_DECIMAL(
            raw_data:monthly_rent::STRING,
            18,
            2
        ) AS monthly_rent,

        TRY_TO_NUMBER(
            raw_data:size_sq_ft::STRING
        ) AS size_sq_ft,

        TRY_TO_NUMBER(
            raw_data:employee_count::STRING
        ) AS employee_count,

        raw_data:is_active::BOOLEAN AS is_active,


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

        UPPER(
            TRIM(raw_data:address:zip_code::STRING)
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
                UPPER(
                    TRIM(raw_data:address:zip_code::STRING)
                ),
                ''
            )

        ) AS full_address,

  

        CASE

            WHEN REGEXP_LIKE(
                LOWER(TRIM(raw_data:email::STRING)),
                '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
            )

            THEN LOWER(
                TRIM(raw_data:email::STRING)
            )

            ELSE NULL

        END AS email,

        REGEXP_REPLACE(
            TRIM(raw_data:phone_number::STRING),
            '[^0-9]',
            ''
        ) AS phone_number,


        TRIM(
            raw_data:operating_hours:weekdays::STRING
        ) AS weekdays,

        TRIM(
            raw_data:operating_hours:weekends::STRING
        ) AS weekends,

        TRIM(
            raw_data:operating_hours:holidays::STRING
        ) AS holidays,

      

        ARRAY_TO_STRING(
            raw_data:services,
            ', '
        ) AS services,

      

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src

),

store_final AS (

    SELECT

    

        store_id,

        store_name,

        store_type,

        region,

        manager_id,

        opening_date,

        last_modified_date,

        current_sales,

        sales_target,

        monthly_rent,

        size_sq_ft,

        employee_count,

        is_active,

        street,

        city,

        state,

        country,

        zip_code,

        full_address,

        email,

        phone_number,

        weekdays,

        weekends,

        holidays,

        services,

  

        CASE

            WHEN size_sq_ft IS NULL
                THEN NULL

            WHEN size_sq_ft < 5000
                THEN 'Small'

            WHEN size_sq_ft >= 5000
             AND size_sq_ft <= 10000
                THEN 'Medium'

            WHEN size_sq_ft > 10000
                THEN 'Large'

            ELSE NULL

        END AS store_size_category,



        CASE

            WHEN opening_date IS NULL
                THEN NULL

            WHEN opening_date > CURRENT_DATE()
                THEN NULL

            ELSE

                DATEDIFF(
                    YEAR,
                    opening_date,
                    CURRENT_DATE()
                )

                -

                CASE

                    WHEN DATE_FROM_PARTS(
                        YEAR(CURRENT_DATE()),
                        MONTH(opening_date),
                        DAY(opening_date)
                    ) > CURRENT_DATE()

                    THEN 1

                    ELSE 0

                END

        END AS store_age_years,

  

        CASE

            WHEN sales_target IS NOT NULL
             AND sales_target > 0
             AND current_sales IS NOT NULL

            THEN ROUND(
                (
                    current_sales / sales_target
                ) * 100,
                2
            )

            ELSE NULL

        END AS sales_target_achievement_percentage,

   

        CASE

            WHEN size_sq_ft IS NOT NULL
             AND size_sq_ft > 0
             AND current_sales IS NOT NULL

            THEN ROUND(
                current_sales / size_sq_ft,
                2
            )

            ELSE NULL

        END AS revenue_per_sq_ft,

 

        CASE

            WHEN employee_count IS NOT NULL
             AND employee_count > 0
             AND current_sales IS NOT NULL

            THEN ROUND(
                current_sales / employee_count,
                2
            )

            ELSE NULL

        END AS employee_efficiency,

 

        CASE

            WHEN sales_target IS NOT NULL
             AND sales_target > 0
             AND current_sales IS NOT NULL
             AND (
                 current_sales / sales_target
             ) * 100 < 90

            THEN 'Yes'

            ELSE 'No'

        END AS performance_issue_flag,



        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM store_clean

)

SELECT *

FROM store_final