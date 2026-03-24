"""
Glue ETL Job - US Census MRTS (Monthly Retail Trade Sales)
Reads raw CSV from s3://.../raw/retail_sales/ingest_date=YYYY-MM-DD/
Transforms to curated Parquet at s3://.../curated/retail_sales/year=YYYY/month=MM/

Parameters: RAW_S3_PREFIX, CURATED_S3_PREFIX, GLUE_DATABASE, TABLE_NAME, INGEST_DATE (optional)
"""

import logging
import sys
from typing import Optional

import boto3
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import DoubleType, IntegerType

# Configure logging
logging.basicConfig(
    format="%(asctime)s %(levelname)s %(message)s",
    level=logging.INFO,
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

# Required args
required_args = ["JOB_NAME", "RAW_S3_PREFIX", "CURATED_S3_PREFIX", "GLUE_DATABASE", "TABLE_NAME"]

# INGEST_DATE is optional - parse manually to avoid getResolvedOptions requiring it
args = getResolvedOptions(sys.argv, required_args)
ingest_date = None
for i, a in enumerate(sys.argv):
    if a == "--INGEST_DATE" and i + 1 < len(sys.argv):
        ingest_date = sys.argv[i + 1].strip() or None
        break

raw_prefix = args["RAW_S3_PREFIX"].rstrip("/")
curated_prefix = args["CURATED_S3_PREFIX"].rstrip("/")
database = args["GLUE_DATABASE"]
table_name = args["TABLE_NAME"]

if ingest_date:
    raw_path = f"{raw_prefix}/ingest_date={ingest_date}/"
else:
    raw_path = f"{raw_prefix}/"

logger.info("raw_path=%s", raw_path)
logger.info("curated_prefix=%s", curated_prefix)
logger.info("GLUE_DATABASE=%s TABLE_NAME=%s", database, table_name)
print(f"[MRTS ETL] raw_path={raw_path} curated_prefix={curated_prefix}", flush=True)

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)


def read_mrts_csv(spark, path: str) -> Optional[DataFrame]:
    """
    Read MRTS space-separated format.
    Census format: YEAR JAN FEB MAR ... (multiple spaces between columns)
    Spark CSV doesn't support regex sep; use text + split.
    """
    try:
        df = spark.read.text(path)
        # Split on whitespace: collapse multiple spaces to single, then split
        df = df.withColumn("parts", F.split(F.trim(F.regexp_replace(F.col("value"), "\\\\s+", " ")), " "))
        df = df.withColumn("part_count", F.size(F.col("parts")))
        # Keep only rows with 13+ parts and numeric first part (year, excludes headers)
        df = df.filter((F.col("part_count") >= 13) & (F.col("parts").getItem(0).rlike(r"^\d{4}$")))
        if df.count() == 0:
            return None
        # Build schema: _c0=year, _c1.._c12=months
        select_exprs = [F.col("parts").getItem(0).alias("_c0")]
        for i in range(1, 13):
            select_exprs.append(F.col("parts").getItem(i).alias(f"_c{i}"))
        return df.select(select_exprs)
    except Exception as e:
        logger.warning("Read failed for %s: %s", path, e)
        return None


def transform_mrts_simple(
    df: DataFrame, category: str = "retail_and_food_services"
) -> Optional[DataFrame]:
    """
    Unpivot MRTS: year, jan, feb, ... -> (year, month, category, sales)
    Sales are in millions of dollars. Filters to valid year rows (1992+).
    """
    cols = df.columns
    if len(cols) < 13:
        logger.warning("Expected 13 columns (year + 12 months), got %d", len(cols))
        return None

    year_col = cols[0]
    month_vals = cols[1:13]

    months = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    exprs = []
    for i, m in enumerate(months):
        c = month_vals[i] if i < len(month_vals) else None
        if c:
            exprs.append(F.struct(F.lit(m).alias("month"), F.col(c).cast(DoubleType()).alias("sales")))

    if not exprs:
        return None

    result = (
        df.select(
            F.col(year_col).cast(IntegerType()).alias("year"),
            F.array(*exprs).alias("months"),
        )
        .select("year", F.explode("months").alias("m"))
        .select(
            "year",
            F.col("m.month").alias("month"),
            F.col("m.sales").alias("sales"),
        )
        .withColumn("category", F.lit(category))
        .filter(
            F.col("year").isNotNull()
            & F.col("month").isNotNull()
            & F.col("sales").isNotNull()
        )
        .filter((F.col("year") >= 1992) & (F.col("year") <= 2030))
        .filter((F.col("sales") > 1000) & (F.col("sales") < 1e7))  # Exclude seasonal factors
    )

    return result


# List raw files
s3 = boto3.client("s3")
parts = raw_prefix.replace("s3://", "").split("/")
bucket = parts[0]
prefix = "/".join(parts[1:]) if len(parts) > 1 else ""

paginator = s3.get_paginator("list_objects_v2")
file_keys = []
for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
    if "Contents" not in page:
        continue
    for obj in page["Contents"]:
        key = obj["Key"]
        if key.endswith(".csv") or key.endswith(".txt"):
            file_keys.append(key)

logger.info("Files found: %d", len(file_keys))
print(f"[MRTS ETL] Files found: {len(file_keys)}", flush=True)

if len(file_keys) == 0:
    logger.info("No raw files found - job completes successfully")
    job.commit()
else:
    # Read and transform
    all_dfs = []
    for key in file_keys:
        full_path = f"s3://{bucket}/{key}"
        df = read_mrts_csv(spark, full_path)
        if df is not None:
            out = transform_mrts_simple(df)
            if out is not None:
                all_dfs.append(out)

    if not all_dfs:
        logger.info("No data could be transformed - job completes successfully")
        print("[MRTS ETL] No data could be transformed (transform returned None for all files)", flush=True)
        job.commit()
    else:
        combined = all_dfs[0]
        for d in all_dfs[1:]:
            combined = combined.unionByName(d, allowMissingColumns=True)

        combined = combined.dropDuplicates(["year", "month", "category"])

        # Add date (first of month) for analytics
        combined = combined.withColumn(
            "date",
            F.date_format(
                F.to_date(
                    F.concat(
                        F.col("year").cast("string"),
                        F.lpad(F.col("month").cast("string"), 2, "0"),
                        F.lit("01"),
                    ),
                    "yyyyMMdd",
                ),
                "yyyy-MM-dd",
            ),
        )

        # Write Parquet partitioned by year, month
        output_path = f"{curated_prefix}/"
        logger.info("Writing Parquet to %s", output_path)
        print(f"[MRTS ETL] Writing Parquet to: {output_path}", flush=True)

        combined.write.mode("overwrite").partitionBy("year", "month").format("parquet").option(
            "compression", "snappy"
        ).save(output_path)

        # Register in Glue Catalog (Crawler can also discover; this enables immediate querying)
        spark.sql(f"CREATE DATABASE IF NOT EXISTS `{database}`")
        spark.sql(f"""
            CREATE TABLE IF NOT EXISTS `{database}`.`{table_name}` (
                category STRING,
                sales DOUBLE,
                date STRING
            )
            USING PARQUET
            PARTITIONED BY (year INT, month INT)
            LOCATION '{curated_prefix}/'
        """)
        try:
            spark.sql(f"MSCK REPAIR TABLE `{database}`.`{table_name}`")
        except Exception as e:
            logger.warning("MSCK REPAIR failed: %s", e)

        record_count = combined.count()
        logger.info("Job complete: %d records written", record_count)
        print(f"[MRTS ETL] Job complete: {record_count} records written to {output_path}", flush=True)
        job.commit()
