{{ config(
    materialized = 'table',
    schema = 'SILVER'
) }}

WITH current_suppliers AS (

    SELECT *

    FROM {{ ref('snapshot_supplier') }}

    WHERE dbt_valid_to IS NULL

),

supplier_cleaned AS (

    SELECT

        -------------------------------------------------
        -- Natural Key
        -------------------------------------------------

        TRIM(
            supplier_id
        ) AS supplier_id,

        -------------------------------------------------
        -- Supplier Name
        -------------------------------------------------

        INITCAP(
            TRIM(raw_data:supplier_name::STRING)
        ) AS supplier_name,

        -------------------------------------------------
        -- Supplier Type
        -------------------------------------------------

        INITCAP(
            TRIM(raw_data:supplier_type::STRING)
        ) AS supplier_type,

        -------------------------------------------------
        -- Contact Information
        -------------------------------------------------

        INITCAP(
            TRIM(
                raw_data:contact_information:contact_person::STRING
            )
        ) AS contact_person,

        LOWER(
            TRIM(
                raw_data:contact_information:email::STRING
            )
        ) AS email,

        REGEXP_REPLACE(
            TRIM(
                raw_data:contact_information:phone::STRING
            ),
            '[^0-9]',
            ''
        ) AS phone_number,

        INITCAP(
            TRIM(
                raw_data:contact_information:address::STRING
            )
        ) AS address,

        -------------------------------------------------
        -- Payment Terms
        -------------------------------------------------

        UPPER(
            TRIM(
                raw_data:payment_terms::STRING
            )
        ) AS payment_terms,

        -------------------------------------------------
        -- Additional Supplier Attributes
        -------------------------------------------------

        TRIM(
            raw_data:tax_id::STRING
        ) AS tax_id,

        LOWER(
            TRIM(
                raw_data:website::STRING
            )
        ) AS website,

        raw_data:is_active::BOOLEAN
            AS is_active,

        INITCAP(
            TRIM(
                raw_data:preferred_carrier::STRING
            )
        ) AS preferred_carrier,

        TRY_TO_NUMBER(
            raw_data:lead_time_days::STRING
        ) AS lead_time_days,

        TRY_TO_NUMBER(
            raw_data:minimum_order_quantity::STRING
        ) AS minimum_order_quantity,

        UPPER(
            TRIM(
                raw_data:credit_rating::STRING
            )
        ) AS credit_rating,

        -------------------------------------------------
        -- Dates
        -------------------------------------------------

        TRY_TO_DATE(
            raw_data:last_modified_date::STRING,
            'YYYY-MM-DD'
        ) AS last_modified_date,

        TRY_TO_DATE(
            raw_data:last_order_date::STRING,
            'YYYY-MM-DD'
        ) AS last_order_date,

        TRY_TO_DATE(
            raw_data:contract_details:start_date::STRING,
            'YYYY-MM-DD'
        ) AS contract_start_date,

        TRY_TO_DATE(
            raw_data:contract_details:end_date::STRING,
            'YYYY-MM-DD'
        ) AS contract_end_date,

        -------------------------------------------------
        -- Contract Information
        -------------------------------------------------

        TRIM(
            raw_data:contract_details:contract_id::STRING
        ) AS contract_id,

        raw_data:contract_details:exclusivity::BOOLEAN
            AS contract_exclusivity,

        raw_data:contract_details:renewal_option::BOOLEAN
            AS contract_renewal_option,

        -------------------------------------------------
        -- Supplier Categories
        -------------------------------------------------

        ARRAY_TO_STRING(
            raw_data:categories_supplied,
            ', '
        ) AS categories_supplied,

        -------------------------------------------------
        -- Performance Metrics
        -------------------------------------------------

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:average_delay_days::STRING,
            10,
            2
        ) AS average_delay_days,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:defect_rate::STRING,
            10,
            2
        ) AS defect_rate,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:on_time_delivery_rate::STRING,
            10,
            2
        ) AS on_time_delivery_rate,

        INITCAP(
            TRIM(
                raw_data:performance_metrics:quality_rating::STRING
            )
        ) AS quality_rating,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:response_time_hours::STRING,
            10,
            2
        ) AS response_time_hours,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:returns_percentage::STRING,
            10,
            2
        ) AS returns_percentage,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM current_suppliers

),

final AS (

    SELECT

        -------------------------------------------------
        -- Gold DIM_Supplier fields
        -------------------------------------------------

        supplier_id,

        supplier_name,

        supplier_type,

        contact_person,

        email,

        phone_number,

        address,

        payment_terms,

        -------------------------------------------------
        -- Additional Supplier Attributes
        -------------------------------------------------

        tax_id,

        website,

        is_active,

        preferred_carrier,

        lead_time_days,

        minimum_order_quantity,

        credit_rating,

        last_modified_date,

        last_order_date,

        contract_id,

        contract_start_date,

        contract_end_date,

        contract_exclusivity,

        contract_renewal_option,

        categories_supplied,

        average_delay_days,

        defect_rate,

        on_time_delivery_rate,

        quality_rating,

        response_time_hours,

        returns_percentage,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM supplier_cleaned

)

SELECT *

FROM final