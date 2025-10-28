terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
resource "aws_cloudwatch_log_group" "warmer_logs" {
  region            = var.region
  name              = "/aws/lambda/${var.function_to_warm}-warmer"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "warmer_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

data "archive_file" "warmer_code" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/function.zip"
}

resource "aws_lambda_function" "warmer_function" {
  region           = var.region
  depends_on       = [aws_cloudwatch_log_group.warmer_logs]
  architectures    = ["arm64"]
  filename         = data.archive_file.warmer_code.output_path
  runtime          = "nodejs22.x"
  handler          = "lambda.handler"
  source_code_hash = data.archive_file.warmer_code.output_base64sha256
  role             = aws_iam_role.warmer_iam_role.arn
  function_name    = "${var.function_to_warm}-warmer"
  description      = "Scheduled invocation to warm ${var.num_desired_warm_instances} instances of function ${var.function_to_warm}."
  memory_size      = 256
  timeout          = 15
  environment {
    variables = {
      LAMBDA_NAME   = var.function_to_warm
      NUM_INSTANCES = var.num_desired_warm_instances
      IS_STREAMING = tostring(var.is_streaming_lambda)
    }
  }
}

resource "aws_lambda_alias" "warmer_function_alias" {
  region           = var.region
  name             = "live"
  description      = "Live environment alias"
  function_name    = aws_lambda_function.warmer_function.arn
  function_version = aws_lambda_function.warmer_function.version
}

resource "aws_iam_role_policy" "warmer_log_write_policy" {
  name = "warmer_log_write_policy"
  role = aws_iam_role.warmer_iam_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.warmer_logs.arn}:*"
      },
    ]
  })
}


resource "aws_iam_role_policy" "warmer_lambda_invoke_policy" {
  name = "warmer_lambda_invoke_policy"
  role = aws_iam_role.warmer_iam_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "lambda:InvokeFunction"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${var.function_to_warm}"
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "warmer_schedule" {
  region              = var.region
  description         = "Schedule to run warmer for ${var.function_to_warm}"
  schedule_expression = var.invoke_rate_string
  state               = "ENABLED"
}

resource "aws_lambda_permission" "warmer_lambda_permission" {
  region        = var.region
  function_name = aws_lambda_function.warmer_function.function_name
  action        = "lambda:InvokeFunction"
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.warmer_schedule.arn
}

resource "aws_cloudwatch_event_target" "warmer_invoke_target" {
  region = var.region
  rule   = aws_cloudwatch_event_rule.warmer_schedule.name
  arn    = aws_lambda_function.warmer_function.arn
}
