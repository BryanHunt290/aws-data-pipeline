"""
Lambda - Trigger Glue ETL job
Invoked by Step Functions or directly. Starts the Glue transform job and returns the run ID.
"""

import json
import boto3
import os

glue = boto3.client("glue")
JOB_NAME = os.environ.get("GLUE_JOB_NAME", "")


def lambda_handler(event, context):
    if not JOB_NAME:
        return {"statusCode": 500, "body": "GLUE_JOB_NAME not configured"}

    response = glue.start_job_run(JobName=JOB_NAME)
    run_id = response["JobRunId"]

    return {
        "statusCode": 200,
        "jobRunId": run_id,
        "jobName": JOB_NAME
    }
