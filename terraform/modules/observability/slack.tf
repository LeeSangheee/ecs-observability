# =============================================================================
# Slack 알림 — Lambda + SNS Subscription
#
# CloudWatch Alarm → SNS Topic → Lambda → Slack Webhook
#
# alarm_slack_webhook_url 변수가 설정된 경우에만 리소스가 생성됩니다.
# Webhook URL은 환경변수로 주입하세요:
#   export TF_VAR_alarm_slack_webhook_url="https://hooks.slack.com/services/..."
# =============================================================================

locals {
  create_slack = var.alarm_slack_webhook_url != ""
}

# -----------------------------------------------------------------------------
# Lambda 소스 코드 ZIP 패키징
# -----------------------------------------------------------------------------
data "archive_file" "slack_notifier" {
  count = local.create_slack ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/slack_notifier.py"
  output_path = "${path.module}/lambda/.build/slack_notifier.zip"
}

# -----------------------------------------------------------------------------
# Lambda 실행 IAM Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "slack_lambda" {
  count = local.create_slack ? 1 : 0

  name        = "${var.project}-${var.environment}-slack-notifier-role"
  description = "Slack Notifier Lambda execution role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# CloudWatch Logs 쓰기 권한 (Lambda 기본 로깅)
resource "aws_iam_role_policy_attachment" "slack_lambda_logs" {
  count = local.create_slack ? 1 : 0

  role       = aws_iam_role.slack_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "slack_notifier" {
  count = local.create_slack ? 1 : 0

  function_name = "${var.project}-${var.environment}-slack-notifier"
  description   = "SNS → Slack Webhook 알림 전송"
  role          = aws_iam_role.slack_lambda[0].arn

  filename         = data.archive_file.slack_notifier[0].output_path
  source_code_hash = data.archive_file.slack_notifier[0].output_base64sha256
  handler          = "slack_notifier.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.alarm_slack_webhook_url
      ENVIRONMENT       = var.environment
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-slack-notifier"
  })
}

# -----------------------------------------------------------------------------
# SNS → Lambda 연결
# -----------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_sns" {
  count = local.create_slack ? 1 : 0

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarms.arn
}

resource "aws_sns_topic_subscription" "slack_lambda" {
  count = local.create_slack ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier[0].arn
}
