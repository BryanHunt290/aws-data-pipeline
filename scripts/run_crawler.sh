#!/bin/bash
# Run Glue Crawler to catalog S3 processed/ data for Athena
set -e
CRAWLER="data-pipeline-demo-crawler-processed"
aws glue start-crawler --name "$CRAWLER"
echo "Crawler started. Wait ~1-2 min, then run dashboard."
