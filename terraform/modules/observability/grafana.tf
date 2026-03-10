# =============================================================================
# AMG (Amazon Managed Grafana) — Workspace + IAM Role
#
# AMG는 완전 관리형 Grafana 서비스입니다.
# AMP, CloudWatch, X-Ray를 데이터소스로 연결하여 통합 대시보드를 제공합니다.
#
# 인증 방식: SERVICE_MANAGED (IAM Identity Center 불필요)
# API Key로 대시보드 프로비저닝이 가능합니다.
#
# 데이터소스 연결 흐름:
#   AMG Workspace → IAM Role (assume) → AMP Query / CloudWatch Read / X-Ray Read
# =============================================================================

# -----------------------------------------------------------------------------
# Data: 현재 AWS 계정 정보 (IAM 정책 ARN 구성에 사용)
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# AMG Workspace
#
# account_access_type: CURRENT_ACCOUNT (단일 계정)
# authentication_providers: AWS_SSO (SERVICE_MANAGED 모드에서도 필수 설정)
# permission_type: SERVICE_MANAGED (Terraform으로 완전 자동화)
# -----------------------------------------------------------------------------
resource "aws_grafana_workspace" "main" {
  name                     = "${var.project}-${var.environment}"
  description              = "${var.project} ${var.environment} 환경 모니터링 대시보드"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn

  # Grafana 버전
  grafana_version = "10.4"

  # 데이터소스 플러그인 자동 활성화
  data_sources = [
    "AMAZON_OPENSEARCH_SERVICE",
    "CLOUDWATCH",
    "PROMETHEUS",
    "XRAY"
  ]

  # 알림 설정 (SNS 연동)
  notification_destinations = ["SNS"]

  configuration = jsonencode({
    plugins = {
      pluginAdminEnabled = true
    }
    unifiedAlerting = {
      enabled = true
    }
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-grafana"
  })
}

# -----------------------------------------------------------------------------
# AMG IAM Role
#
# AMG가 AWS 데이터소스(AMP, CloudWatch, X-Ray)에 접근하기 위한 서비스 역할입니다.
# grafana.amazonaws.com 서비스 프린시펄이 이 역할을 assume합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "grafana" {
  name        = "${var.project}-${var.environment}-grafana-role"
  description = "AMG Workspace Role - AMP/CloudWatch/X-Ray read access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 정책 1: AMP 쿼리 권한
# AMG에서 AMP 데이터소스를 조회할 때 필요합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "grafana_amp" {
  name = "${var.project}-${var.environment}-grafana-amp-policy"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AMPQuery"
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 정책 2: CloudWatch 읽기 권한
# AMG에서 CloudWatch Metrics/Logs를 대시보드에 표시할 때 필요합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "${var.project}-${var.environment}-grafana-cw-policy"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 정책 3: X-Ray 읽기 권한
# AMG에서 X-Ray 트레이스를 조회할 때 필요합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "grafana_xray" {
  name = "${var.project}-${var.environment}-grafana-xray-policy"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "XRayRead"
        Effect = "Allow"
        Action = [
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries",
          "xray:BatchGetTraces",
          "xray:GetServiceGraph",
          "xray:GetTraceGraph",
          "xray:GetTraceSummaries",
          "xray:GetGroups",
          "xray:GetGroup",
          "xray:ListTagsForResource",
          "xray:GetTimeSeriesServiceStatistics",
          "xray:GetInsightSummaries",
          "xray:GetInsight",
          "xray:GetInsightEvents",
          "xray:GetInsightImpactGraph"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 정책 4: SNS 알림 전송 권한
# AMG Unified Alerting에서 SNS로 알림을 보낼 때 필요합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "grafana_sns" {
  name = "${var.project}-${var.environment}-grafana-sns-policy"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alarms.arn
      }
    ]
  })
}
