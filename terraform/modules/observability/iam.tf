# =============================================================================
# observability 모듈 — ADOT Task Role IAM 정책
#
# ADOT Sidecar 컨테이너가 AWS 서비스에 데이터를 쓰기 위한 최소 권한입니다.
# ECS Task Role (task_role_arn)에 연결됩니다.
#
# 권한 분류:
#   1. AMP Remote Write: 메트릭 전송
#   2. X-Ray: 트레이스 전송 + 샘플링 규칙 조회
#   3. CloudWatch Logs: 로그 스트림 생성 + 로그 이벤트 쓰기
# =============================================================================

# ADOT Task Role 생성
# ECS Task 내 컨테이너(App + ADOT Sidecar)가 AWS API를 호출할 때 이 Role이 사용됩니다.
resource "aws_iam_role" "adot_task" {
  name        = "${var.project}-${var.environment}-adot-task-role"
  description = "ADOT Sidecar Task Role — AMP/X-Ray/CloudWatch Logs 최소 권한"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 인라인 정책: AMP Remote Write
#
# 보안 강화: AMP Workspace ARN을 명시하여 다른 AMP Workspace에는 접근 불가
# Resource를 "*"로 설정하면 계정 내 모든 AMP Workspace에 쓸 수 있어 위험합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "adot_amp" {
  name = "${var.project}-${var.environment}-adot-amp-policy"
  role = aws_iam_role.adot_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AMPRemoteWrite"
        Effect = "Allow"
        Action = [
          # 메트릭 원격 쓰기 (ADOT prometheusremotewrite exporter)
          "aps:RemoteWrite"
        ]
        # 특정 AMP Workspace만 허용 (최소 권한 원칙)
        Resource = aws_amp_workspace.main.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 인라인 정책: X-Ray
#
# xray:GetSamplingRules, xray:GetSamplingTargets 는 ADOT이 X-Ray 샘플링
# 규칙을 동적으로 조회하기 위해 필요합니다.
# 샘플링 규칙은 xray.tf에서 정의합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "adot_xray" {
  name = "${var.project}-${var.environment}-adot-xray-policy"
  role = aws_iam_role.adot_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "XRayTraceWrite"
        Effect = "Allow"
        Action = [
          # 트레이스 세그먼트 전송
          "xray:PutTraceSegments",
          # 텔레메트리 레코드 전송 (X-Ray 내부 메트릭)
          "xray:PutTelemetryRecords",
          # 샘플링 규칙 조회 (ADOT이 동적 샘플링 결정에 사용)
          "xray:GetSamplingRules",
          # 샘플링 대상(목표 비율) 조회
          "xray:GetSamplingTargets"
        ]
        # X-Ray는 리소스 레벨 제어를 지원하지 않아 * 필수
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 인라인 정책: CloudWatch Logs
#
# 보안 강화: 특정 Log Group ARN만 허용하여 다른 로그 그룹 접근 불가
#
# [주의] logs:CreateLogGroup은 여기서 허용하지 않습니다.
# Log Group은 Terraform(cloudwatch.tf)에서 미리 생성하고,
# ADOT은 기존 Log Group에 스트림과 이벤트만 씁니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "adot_logs" {
  name = "${var.project}-${var.environment}-adot-logs-policy"
  role = aws_iam_role.adot_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          # 새 로그 스트림 생성 (ADOT이 Task ID 기반 스트림을 생성할 때 필요)
          "logs:CreateLogStream",
          # 로그 이벤트 쓰기
          "logs:PutLogEvents"
        ]
        # 특정 Log Group 하위 스트림만 허용
        # :* 는 해당 Log Group의 모든 Log Stream에 대한 접근을 의미
        Resource = [
          "${aws_cloudwatch_log_group.app.arn}:*",
          "${aws_cloudwatch_log_group.adot.arn}:*"
        ]
      }
    ]
  })
}

# DescribeLogStreams: ADOT이 기존 스트림 존재 여부를 확인할 때 필요
# 모든 Log Group에 대해 허용하되 민감한 쓰기 권한은 위에서 제한합니다.
resource "aws_iam_role_policy" "adot_logs_describe" {
  name = "${var.project}-${var.environment}-adot-logs-describe-policy"
  role = aws_iam_role.adot_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.app.arn}:*",
          "${aws_cloudwatch_log_group.adot.arn}:*"
        ]
      }
    ]
  })
}
