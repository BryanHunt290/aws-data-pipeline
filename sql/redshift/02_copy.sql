-- Redshift COPY: Load Parquet from S3 into raw.sales_processed
-- Replace {BUCKET} and {IAM_ROLE_ARN} from terraform output

TRUNCATE TABLE raw.sales_processed;

COPY raw.sales_processed (category, total_quantity, total_revenue, transaction_count, year, month)
FROM 's3://{BUCKET}/processed/'
IAM_ROLE '{IAM_ROLE_ARN}'
FORMAT AS PARQUET;
