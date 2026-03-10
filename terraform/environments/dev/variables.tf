# =============================================================================
# dev 환경 — 입력 변수 정의
#
# 실제 값은 terraform.tfvars에서 설정합니다.
# 민감한 값(비밀번호, API 키 등)은 환경변수(TF_VAR_*)나 Secrets Manager로 주입하세요.
# =============================================================================

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "프로젝트 이름 (리소스 이름 prefix)"
  type        = string
  default     = "supplement-rec"
}

variable "environment" {
  description = "배포 환경"
  type        = string
  default     = "dev"
}

variable "app_port" {
  description = "애플리케이션 포트"
  type        = number
  default     = 8000
}

variable "create_amp_endpoint" {
  description = "AMP VPC Endpoint 생성 여부"
  type        = bool
  default     = false
}

variable "alarm_email" {
  description = "알람 수신 이메일 (빈 문자열이면 미설정)"
  type        = string
  default     = ""
}

variable "database_url" {
  description = "애플리케이션 데이터베이스 URL"
  type        = string
  sensitive   = true
}

variable "jwt_secret_key" {
  description = "JWT 서명 키"
  type        = string
  sensitive   = true
}

variable "alarm_slack_webhook_url" {
  description = "Slack Webhook URL (빈 문자열이면 미설정)"
  type        = string
  default     = ""
  sensitive   = true
}
