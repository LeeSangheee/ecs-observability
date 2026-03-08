# =============================================================================
# SNS Topic — 알람 알림 허브
#
# CloudWatch Alarms(environments/dev/alarms.tf)가 이 Topic으로 알림을 보냅니다.
# SNS Topic은 observability 모듈에서 관리하고, ARN을 outputs.tf로 노출합니다.
#
# 알림 흐름:
#   CloudWatch Alarm → SNS Topic → 이메일 Subscription
#                               → [Phase 3] Slack Lambda Subscription
# =============================================================================

resource "aws_sns_topic" "alarms" {
  name         = "${var.project}-${var.environment}-alarms"
  display_name = "${var.project} ${var.environment} 알람"

  tags = var.tags
}

# 이메일 Subscription (alarm_email 변수가 설정된 경우에만 생성)
resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email

  # [중요] 이메일 구독은 수동 확인이 필요합니다.
  # terraform apply 후 수신된 "AWS Notification - Subscription Confirmation" 이메일에서
  # "Confirm subscription" 링크를 클릭해야 알림이 실제로 전달됩니다.
}

# =============================================================================
# [Phase 3 Slack 연동 안내]
#
# Slack Webhook 연동은 Lambda 함수를 SNS Subscriber로 등록합니다.
# Lambda는 SNS 메시지를 파싱하여 Slack Block Kit 포맷으로 변환합니다.
#
# 구현 예정 리소스:
#   - aws_lambda_function "slack_notifier"
#   - aws_lambda_permission "allow_sns"
#   - aws_sns_topic_subscription "slack_lambda"
#
# 대안: AWS Chatbot을 사용하면 Lambda 없이 Slack/Teams 연동이 가능합니다.
#   - aws_chatbot_slack_channel_configuration (Terraform 지원 제한적)
#   - AWS Console에서 직접 설정하는 것이 더 편리합니다.
# =============================================================================
