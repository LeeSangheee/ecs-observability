# =============================================================================
# CloudWatch — Log Groups + Metric Filters
#
# Log Groups:
#   1. /ecs/{project}-{environment}         — App Container 로그
#   2. /ecs/{project}-{environment}/adot-collector — ADOT Sidecar 로그
#
# Metric Filters:
#   CloudWatch Logs에서 에러 패턴을 찾아 커스텀 메트릭으로 변환합니다.
#   AMP(Prometheus)로 메트릭이 전송되기 전, CloudWatch 기반 빠른 알람에 활용합니다.
# =============================================================================

# -----------------------------------------------------------------------------
# 1-a. App Container Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}-${var.environment}"
  retention_in_days = var.log_retention_days

  # 운영 환경 보안: KMS 키로 로그 암호화 (선택사항)
  # 건강 데이터가 포함될 수 있어 암호화 권장
  # kms_key_id = aws_kms_key.logs.arn

  tags = merge(var.tags, {
    Name = "/ecs/${var.project}-${var.environment}"
  })
}

# -----------------------------------------------------------------------------
# 1-b. ADOT Sidecar Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "adot" {
  name              = "/ecs/${var.project}-${var.environment}/adot-collector"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "/ecs/${var.project}-${var.environment}/adot-collector"
  })
}

# =============================================================================
# 2. Metric Filters — 로그에서 메트릭 추출
#
# CloudWatch Logs Insights보다 저렴하게 에러 패턴을 메트릭으로 변환합니다.
# 필터 패턴은 JSON 로그 또는 텍스트 로그 모두 지원합니다.
# =============================================================================

# 에러 로그 카운트 메트릭
# 패턴: "ERROR" 또는 "error" 키워드를 포함하는 로그 라인
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.project}-${var.environment}-error-count"
  pattern        = "?ERROR ?error ?Error"
  log_group_name = aws_cloudwatch_log_group.app.name

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "${var.project}/${var.environment}"
    value         = "1"
    default_value = "0" # 에러가 없는 기간은 0으로 채움 (알람 데이터 공백 방지)
    unit          = "Count"
  }
}

# 5xx HTTP 에러 메트릭 (JSON 로그 형식 기준)
# 로그에 "statusCode": 5xx 패턴이 있는 경우 추출합니다.
# 실제 로그 형식에 맞게 패턴을 조정하세요.
resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  name           = "${var.project}-${var.environment}-http-5xx"
  pattern        = "{ $.statusCode >= 500 }"
  log_group_name = aws_cloudwatch_log_group.app.name

  metric_transformation {
    name          = "Http5xxCount"
    namespace     = "${var.project}/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ADOT Sidecar 에러 메트릭
# ADOT이 AMP/X-Ray로 데이터를 전송하는 데 실패하면 이 메트릭이 증가합니다.
resource "aws_cloudwatch_log_metric_filter" "adot_error" {
  name           = "${var.project}-${var.environment}-adot-error"
  pattern        = "?exporter_send_failed ?Exporter ?error"
  log_group_name = aws_cloudwatch_log_group.adot.name

  metric_transformation {
    name          = "AdotExporterError"
    namespace     = "${var.project}/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}
