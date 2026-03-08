# =============================================================================
# ecs 모듈 — 출력값 정의
# =============================================================================

output "cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "ECS Cluster 이름"
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "ECS Service 이름"
  value       = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "ECS Task Definition ARN"
  value       = aws_ecs_task_definition.app.arn
}

output "task_execution_role_arn" {
  description = "Task Execution Role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "alb_dns_name" {
  description = "ALB DNS 이름 (애플리케이션 접속 URL)"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN (CloudWatch Alarms 메트릭 참조용)"
  value       = aws_lb.main.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch 메트릭 dimensions 에 사용)"
  value       = aws_lb.main.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target Group ARN suffix (CloudWatch 메트릭 dimensions 에 사용)"
  value       = aws_lb_target_group.app.arn_suffix
}

output "ecs_tasks_sg_id" {
  description = "ECS Task 보안 그룹 ID"
  value       = aws_security_group.ecs_tasks.id
}
