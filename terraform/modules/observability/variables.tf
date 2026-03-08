# =============================================================================
# observability 모듈 — 입력 변수 정의
#
# AMP, X-Ray, CloudWatch Log Groups, SNS Topic, IAM(ADOT) 생성에 필요한 변수들입니다.
#
# [알람(CloudWatch Metric Alarms)에 대하여]
# CloudWatch Alarms는 이 모듈이 아닌 environments/dev/alarms.tf에서 생성합니다.
# 이유: Alarms가 ecs 모듈 출력값(ALB ARN suffix)을 참조하는데,
#       ecs 모듈도 이 모듈의 출력값(adot_task_role_arn)을 참조하므로
#       순환 참조가 발생합니다. environments 레벨에서 양쪽을 참조하면 순환이 없습니다.
# =============================================================================

variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "배포 환경 (dev / staging / prod)"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

# account_id: IAM 정책에서 AMP Workspace ARN을 직접 aws_amp_workspace.main.arn으로
# 참조하므로 현재 사용하지 않습니다. 향후 cross-account 설정 시 활성화하세요.
# variable "account_id" {
#   description = "AWS 계정 ID"
#   type        = string
# }

# -----------------------------------------------------------------------------
# SNS 알림 설정
# SNS Topic은 이 모듈에서 생성하고, CloudWatch Alarms(environments 레벨)에서 구독합니다.
# -----------------------------------------------------------------------------
variable "alarm_email" {
  description = "CloudWatch Alarm 알림 이메일 주소. 빈 문자열이면 이메일 subscription 미생성."
  type        = string
  default     = ""
}

variable "alarm_slack_webhook_url" {
  description = "Slack Webhook URL. Phase 3에서 구현 예정."
  type        = string
  default     = ""
  sensitive   = true
}

# 알람 임계값(error_rate_threshold, cpu_threshold)은
# environments/dev/alarms.tf의 locals 블록에서 관리합니다.
# CloudWatch Alarms를 모듈 외부에서 생성하는 구조로 변경되었습니다.

variable "log_retention_days" {
  description = "CloudWatch Logs 보관 기간 (일)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "모든 리소스에 공통으로 적용할 태그 맵"
  type        = map(string)
  default     = {}
}
