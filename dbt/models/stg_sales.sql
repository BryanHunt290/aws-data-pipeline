{{
  config(
    materialized='table',
    schema='raw'
  )
}}

-- Staging: raw sales from Redshift (loaded via COPY from S3)
select * from {{ source('raw', 'sales_processed') }}
