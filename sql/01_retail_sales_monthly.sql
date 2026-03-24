-- retail_sales_monthly: Cleaned base table/view
-- Partition pruning: filter on year, month for performance
-- Run in Athena workgroup from terraform output

CREATE OR REPLACE VIEW retail_sales_monthly AS
SELECT
    year,
    month,
    category,
    sales,
    date,
    sales * 1e6 AS sales_dollars  -- Convert millions to dollars for reporting
FROM retail_sales
WHERE year IS NOT NULL
  AND month IS NOT NULL
  AND sales IS NOT NULL
  AND sales > 0;
