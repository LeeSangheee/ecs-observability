# =============================================================================
# CloudWatch Alarms — dev 환경
#
# [왜 environments/dev/에 있는가?]
# CloudWatch Alarms는 ECS 모듈(ALB ARN suffix, Cluster 이름)과
# Observability 모듈(SNS Topic ARN, Log Group 이름) 양쪽을 모두 참조합니다.
#
# 만약 alarms.tf를 observability 모듈 안에 두면:
#   - ecs 모듈 → observability 모듈의 adot_task_role_arn 참조
#   - observability 모듈 → ecs 모듈의 alb_arn_suffix 참조
#   → Terraform 순환 참조(Cycle) 오류 발생
#
# 해결: Alarms를 모듈 외부인 environments/dev/에서 직접 리소스로 생성합니다.
# 모듈 의존 관계는 단방향(networking → observability + ecs → alarms)으로 유지됩니다.
#
# 알람 목록:
#   1. 에러율 > 1% (5분)
#   2. ECS Running Task < Desired (3분 연속)
#   3. ECS CPU > 80% (10분)
#   4. ADOT 익스포터 오류
#   5. API P99 레이턴시 > 2초 (5분)
# =============================================================================

# =============================================================================
# 알람 임계값 로컬 변수
# terraform.tfvars에서 조정하려면 variables.tf에 변수를 추가하세요.
# =============================================================================
locals {
  alarm_error_rate_threshold = 1   # 에러율 임계값 (%)
  alarm_cpu_threshold        = 80  # CPU 임계값 (%)
  alarm_latency_threshold    = 2   # 레이턴시 임계값 (초)
}

# =============================================================================
# 알람 1: 에러율 (ALB 5xx / 전체 요청 비율)
#
# ALB 메트릭을 사용합니다 (CloudWatch에 자동 수집).
# metric_query로 두 메트릭의 비율을 계산합니다.
#
# [주의] 요청이 전혀 없는 기간(total = 0)에는 division by zero로 INSUFFICIENT_DATA
# treat_missing_data = "notBreaching"으로 이 상황에서 알람이 울리지 않게 합니다.
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.project}-${var.environment}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5   # 5번 연속 (1분 × 5 = 5분)
  threshold           = local.alarm_error_rate_threshold

  metric_query {
    id          = "error_rate"
    expression  = "(errors / total) * 100"
    label       = "에러율 (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = module.ecs.alb_arn_suffix
        TargetGroup  = module.ecs.target_group_arn_suffix
      }
    }
  }

  metric_query {
    id = "total"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = module.ecs.alb_arn_suffix
        TargetGroup  = module.ecs.target_group_arn_suffix
      }
    }
  }

  alarm_description = "에러율이 ${local.alarm_error_rate_threshold}%를 초과했습니다. ECS 로그와 X-Ray 트레이스를 확인하세요."
  alarm_actions     = [module.observability.alarm_sns_topic_arn]
  ok_actions        = [module.observability.alarm_sns_topic_arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# =============================================================================
# 알람 2: ECS Running Task 이상
#
# Container Insights가 수집하는 RunningTaskCount 메트릭을 사용합니다.
# ECS Cluster에서 containerInsights = "enabled" 설정 필요 (ecs/main.tf에서 활성화됨).
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "ecs_running_task_count" {
  alarm_name          = "${var.project}-${var.environment}-ecs-task-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3   # 3분 연속 기준 미달
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 1   # Running Task가 1개 미만이면 알람

  dimensions = {
    ClusterName = module.ecs.cluster_name
    ServiceName = module.ecs.service_name
  }

  alarm_description = "ECS Service Running Task 수가 비정상입니다. ECS 콘솔의 Events 탭에서 오류를 확인하세요."
  alarm_actions     = [module.observability.alarm_sns_topic_arn]
  ok_actions        = [module.observability.alarm_sns_topic_arn]

  # Container Insights 비활성화 상태에서는 데이터 없음 → notBreaching으로 설정
  # Container Insights 활성화 확인 후 "breaching"으로 변경하세요.
  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# =============================================================================
# 알람 3: CPU 사용률 (10분 평균)
#
# ECS Service 수준 CPU 사용률입니다.
# Auto Scaling 목표(70%)보다 높게 설정(80%)하여 스케일 아웃으로도
# 해소되지 않는 지속적 과부하를 감지합니다.
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.project}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 10
  datapoints_to_alarm = 8   # 10분 중 8분 이상 초과 시 알람 (순간 급증 제외)
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = local.alarm_cpu_threshold

  dimensions = {
    ClusterName = module.ecs.cluster_name
    ServiceName = module.ecs.service_name
  }

  alarm_description = "CPU 사용률이 ${local.alarm_cpu_threshold}%를 10분간 초과했습니다. Auto Scaling 동작을 확인하세요."
  alarm_actions     = [module.observability.alarm_sns_topic_arn]
  ok_actions        = [module.observability.alarm_sns_topic_arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# =============================================================================
# 알람 4: ADOT 익스포터 오류
#
# observability/cloudwatch.tf의 Metric Filter(AdotExporterError)를 사용합니다.
# ADOT이 AMP/X-Ray로 전송에 실패하면 메트릭/트레이스가 유실됩니다.
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "adot_exporter_error" {
  alarm_name          = "${var.project}-${var.environment}-adot-exporter-error"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 1   # 1번이라도 발생하면 알람
  metric_name         = "AdotExporterError"
  namespace           = "${var.project}/${var.environment}"
  period              = 300 # 5분
  statistic           = "Sum"
  threshold           = 0

  alarm_description = "ADOT Sidecar가 데이터 전송에 실패했습니다. 관측 데이터가 유실될 수 있습니다."
  alarm_actions     = [module.observability.alarm_sns_topic_arn]
  ok_actions        = [module.observability.alarm_sns_topic_arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# =============================================================================
# 알람 5: API P99 레이턴시
#
# ALB TargetResponseTime P99 통계를 사용합니다.
# SLO 목표: P99 < 2s (추천 API 기준)
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${var.project}-${var.environment}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = local.alarm_latency_threshold

  dimensions = {
    LoadBalancer = module.ecs.alb_arn_suffix
    TargetGroup  = module.ecs.target_group_arn_suffix
  }

  alarm_description = "API P99 레이턴시가 ${local.alarm_latency_threshold}초를 초과했습니다. 추천 알고리즘 성능과 DB 응답 시간을 확인하세요."
  alarm_actions     = [module.observability.alarm_sns_topic_arn]
  ok_actions        = [module.observability.alarm_sns_topic_arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}
