# =============================================================================
# networking 모듈 — 입력 변수 정의
#
# VPC, 서브넷, VPC Endpoint 생성에 필요한 모든 변수를 정의합니다.
# 기본값은 개발 환경 기준으로 설정되어 있습니다.
# =============================================================================

variable "project" {
  description = "프로젝트 이름 (리소스 이름 prefix로 사용)"
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

# -----------------------------------------------------------------------------
# VPC CIDR
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC 전체 CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

# -----------------------------------------------------------------------------
# 서브넷 CIDR — 퍼블릭 (ALB, NAT GW 위치)
# 가용 영역 2개를 사용해 고가용성을 확보합니다.
# -----------------------------------------------------------------------------
variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록 (순서: ap-northeast-2a, ap-northeast-2c)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_azs" {
  description = "퍼블릭 서브넷 가용 영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

# -----------------------------------------------------------------------------
# 서브넷 CIDR — 프라이빗 (ECS Fargate Task 위치)
# ECS Task는 외부 인터넷에 직접 노출되지 않습니다.
# -----------------------------------------------------------------------------
variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록 (순서: ap-northeast-2a, ap-northeast-2c)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_subnet_azs" {
  description = "프라이빗 서브넷 가용 영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

# -----------------------------------------------------------------------------
# VPC Endpoint 생성 여부 플래그
#
# 주의: AMP(aps-workspaces) VPC Endpoint는 서울 리전(ap-northeast-2) 지원 여부가
# 불확실합니다. 미지원 시 NAT Gateway를 경유하므로 create_amp_endpoint = false로
# 두는 것이 안전합니다.
# 참고: https://docs.aws.amazon.com/general/latest/gr/amp-service-endpoints.html
# -----------------------------------------------------------------------------
variable "create_amp_endpoint" {
  description = "AMP(aps-workspaces) VPC Interface Endpoint 생성 여부. 서울 리전 지원 확인 후 활성화하세요."
  type        = bool
  default     = false
}

variable "tags" {
  description = "모든 리소스에 공통으로 적용할 태그 맵"
  type        = map(string)
  default     = {}
}
