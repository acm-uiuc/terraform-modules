terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_caller_identity" "current" {}
resource "aws_cloudwatch_log_group" "warmer_logs" {
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
  output_path = "${path.module}/lambda/function.zip"
}

resource "aws_lambda_function" "warmer_function" {
  depends_on       = [aws_cloudwatch_log_group.warmer_logs]
  architectures    = ["arm64"]
  filename         = data.archive_file.warmer_code.output_path
  runtime          = "nodejs22.x"
  source_code_hash = data.archive_file.warmer_code.output_base64sha256
  role             = aws_iam_role.warmer_iam_role
  function_name    = "${var.function_to_warm}-warmer"
  memory_size      = 256
  timeout          = 15
  environment {
    variables = {
      LAMBDA_NAME   = var.function_to_warm
      NUM_INSTANCES = var.num_desired_warm_instances
    }
  }
}

resource "aws_lambda_alias" "warmer_function_alias" {
  name             = "live"
  description      = "Live environment alias"
  function_name    = aws_lambda_function.warmer_function.arn
  function_version = aws_lambda_function.warmer_function.version
}

resource "aws_iam_role_policy" "warmer_log_write_policy" {
  name = "warmer_log_write_policy"
  role = aws_iam_role.warmer_iam_role
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
        Resource = aws_cloudwatch_log_group.warmer_logs.arn
      },
    ]
  })
}


resource "aws_iam_role_policy" "warmer_lambda_invoke_policy" {
  name = "warmer_lambda_invoke_policy"
  role = aws_iam_role.warmer_iam_role
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "lambda:InvokeFunction"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.function_to_warm}"
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "warmer_schedule" {
  description         = "Schedule to run warmer for ${var.function_to_warm}"
  schedule_expression = var.invoke_rate_string
  state               = "ENABLED"
}

resource "aws_lambda_permission" "warmer_lambda_permission" {
  function_name = "${var.function_to_warm}-warmer"
  action        = "lambda:InvokeFunction"
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.warmer_schedule.arn
}
