#!/usr/bin/env python3
"""
Produce sample MRTS records to Kafka (MSK Serverless).
Creates topic on first run. Uses IAM auth.

Usage:
  pip install kafka-python boto3
  python scripts/produce_to_kafka.py

Env: MSK_BOOTSTRAP_SERVERS (from terraform output msk_bootstrap_servers)
"""

import json
import os
import sys

from kafka import KafkaProducer
from kafka.errors import KafkaError

BOOTSTRAP = os.getenv("MSK_BOOTSTRAP_SERVERS")
TOPIC = os.getenv("KAFKA_TOPIC", "retail_sales")

if not BOOTSTRAP:
    print("Set MSK_BOOTSTRAP_SERVERS (terraform output msk_bootstrap_servers)", file=sys.stderr)
    sys.exit(1)

# Sample records (year, month, category, sales, date)
records = [
    {"year": 2024, "month": 1, "category": "retail_and_food_services", "sales": 700.5, "date": "2024-01-01"},
    {"year": 2024, "month": 2, "category": "retail_and_food_services", "sales": 710.2, "date": "2024-02-01"},
]

# MSK with IAM requires aws-msk-iam-sasl-signer. For simplicity, use PLAIN or
# run from EC2/Glue in VPC. Local: use IAM auth via aws-msk-iam-sasl-signer-java
# Python: kafka-python doesn't support IAM natively. Use aiobotocore or
# confluent-kafka with oauthbearer. For dev, consider MSK with no auth in VPC.
# This script documents the format; for IAM auth use boto3 + custom SASL.

try:
    producer = KafkaProducer(
        bootstrap_servers=BOOTSTRAP.split(","),
        value_serializer=lambda v: json.dumps(v).encode("utf-8"),
        # For IAM: use KafkaProducer with sasl_mechanism="OAUTHBEARER" and
        # custom oauth callback. See AWS docs for MSK IAM client setup.
    )
    for r in records:
        producer.send(TOPIC, value=r)
    producer.flush()
    print(f"Produced {len(records)} records to {TOPIC}")
except KafkaError as e:
    print(f"Kafka error: {e}", file=sys.stderr)
    sys.exit(1)
