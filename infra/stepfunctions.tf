# Step Functions - Glue ETL (Crawlers run separately; Step Functions has no crawler.sync)
# EventBridge - Daily schedule

resource "aws_iam_role" "stepfunctions" {
  name = "${local.name}-stepfunctions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "stepfunctions" {
  name = "glue-job"
  role = aws_iam_role.stepfunctions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "glue:StartJobRun"
        Resource = [aws_glue_job.mrts_etl.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
        Resource = [aws_glue_job.mrts_etl.arn]
      }
    ]
  })
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name}-pipeline"
  role_arn = aws_iam_role.stepfunctions.arn

  definition = jsonencode({
    StartAt = "GlueETL"
    States = {
      GlueETL = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.mrts_etl.name
        }
        End = true
      }
    }
  })
}

# EventBridge - Daily schedule at 06:00 UTC
resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${local.name}-daily"
  description         = "Trigger MRTS pipeline daily"
  schedule_expression = "cron(0 6 * * ? *)"
}

resource "aws_cloudwatch_event_target" "stepfunctions" {
  rule      = aws_cloudwatch_event_rule.daily.name
  target_id = "Pipeline"
  arn       = aws_sfn_state_machine.pipeline.arn
  role_arn  = aws_iam_role.eventbridge.arn
}

resource "aws_iam_role" "eventbridge" {
  name = "${local.name}-eventbridge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_stepfunctions" {
  name = "start-execution"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = [aws_sfn_state_machine.pipeline.arn]
    }]
  })
}
