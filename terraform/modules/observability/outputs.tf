# =============================================================================
# observability 모듈 — 출력값 정의
# =============================================================================

output "amp_workspace_id" {
  description = "AMP Workspace ID"
  value       = aws_amp_workspace.main.id
}

output "amp_workspace_arn" {
  description = "AMP Workspace ARN (IAM 정책 리소스 지정에 사용)"
  value       = aws_amp_workspace.main.arn
}

output "amp_workspace_endpoint" {
  description = "AMP Remote Write Endpoint (ADOT 설정에서 사용)"
  value       = aws_amp_workspace.main.prometheus_endpoint
}

output "adot_task_role_arn" {
  description = "ADOT Task Role ARN (ECS Task Definition에 주입)"
  value       = aws_iam_role.adot_task.arn
}

output "adot_task_role_name" {
  description = "ADOT Task Role 이름"
  value       = aws_iam_role.adot_task.name
}

output "alarm_sns_topic_arn" {
  description = "알람 SNS Topic ARN"
  value       = aws_sns_topic.alarms.arn
}

output "app_log_group_name" {
  description = "App 컨테이너 CloudWatch Log Group 이름"
  value       = aws_cloudwatch_log_group.app.name
}

output "adot_log_group_name" {
  description = "ADOT Sidecar CloudWatch Log Group 이름"
  value       = aws_cloudwatch_log_group.adot.name
}
