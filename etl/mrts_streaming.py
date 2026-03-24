"""
Glue Streaming Job - MRTS retail sales from Kafka to S3
Reads JSON from Kafka topic, writes Parquet to S3 (curated/retail_sales_streaming/)

Parameters: KAFKA_CONNECTION_NAME, KAFKA_TOPIC, CURATED_S3_PREFIX, GLUE_DATABASE, TABLE_NAME
"""

import sys

from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "KAFKA_CONNECTION_NAME", "KAFKA_TOPIC", "CURATED_S3_PREFIX", "GLUE_DATABASE", "TABLE_NAME", "checkpointLocation"],
)

connection_name = args["KAFKA_CONNECTION_NAME"]
topic = args["KAFKA_TOPIC"]
curated_prefix = args["CURATED_S3_PREFIX"].rstrip("/")
database = args["GLUE_DATABASE"]
table_name = args["TABLE_NAME"]
checkpoint = args["checkpointLocation"]

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Read from Kafka stream
kafka_options = {
    "connectionName": connection_name,
    "topicName": topic,
    "startingOffsets": "latest",
}

df_stream = glueContext.create_data_frame_from_options(
    connection_type="kafka",
    connection_options=kafka_options,
    transformation_ctx="kafka_stream",
)

# Parse JSON value (Kafka value column)
schema = "year INT, month INT, category STRING, sales DOUBLE, date STRING"
df_parsed = df_stream.select(
    F.from_json(F.col("value").cast("string"), schema).alias("data")
).select("data.*").filter(
    F.col("year").isNotNull() & F.col("month").isNotNull() & F.col("sales").isNotNull()
)

# Write to S3 in micro-batches (Parquet, partitioned by year/month)
query = (
    df_parsed.writeStream
    .outputMode("append")
    .format("parquet")
    .option("path", f"{curated_prefix}/")
    .option("checkpointLocation", checkpoint)
    .partitionBy("year", "month")
    .option("compression", "snappy")
    .start()
)

query.awaitTermination()
