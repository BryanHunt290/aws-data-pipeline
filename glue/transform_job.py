"""
Glue ETL Job - Transform raw CSV to processed Parquet (partitioned by year, month)
Reads from s3://bucket/raw/, transforms, writes to s3://bucket/processed/year=YYYY/month=MM/
Output schema: category, total_quantity, total_revenue, transaction_count, year, month
"""

import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "INPUT_PATH", "OUTPUT_PATH"]
)

input_path = args["INPUT_PATH"]
output_path = args["OUTPUT_PATH"]

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Read raw CSV
df = spark.read.option("header", "true").option("inferSchema", "true").csv(input_path)

# Transform: add revenue, extract year/month, aggregate by category
df_transformed = (
    df.withColumn("revenue", F.col("quantity") * F.col("unit_price"))
    .withColumn("sale_date", F.to_date(F.col("sale_date")))
    .withColumn("year", F.year(F.col("sale_date")))
    .withColumn("month", F.month(F.col("sale_date")))
    .groupBy("category", "year", "month")
    .agg(
        F.sum("quantity").alias("total_quantity"),
        F.sum("revenue").alias("total_revenue"),
        F.count("*").alias("transaction_count")
    )
)

# Write Parquet (year, month as columns for Redshift COPY)
df_transformed.write.mode("overwrite").parquet(output_path)

job.commit()
