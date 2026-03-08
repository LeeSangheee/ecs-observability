# =============================================================================
# ecs 모듈 — 입력 변수 정의
#
# ECS Cluster, ALB, Task Definition, Service 생성에 필요한 변수들입니다.
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

# -----------------------------------------------------------------------------
# 네트워킹 (networking 모듈 출력값에서 주입)
# -----------------------------------------------------------------------------
variable "vpc_id" {
  description = "ECS Task와 ALB가 배포될 VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록. 현재는 Security Group이 ALB SG를 소스로 사용하므로 직접 참조하지 않습니다. 추후 VPC 피어링 등 CIDR 기반 규칙이 필요할 때 활용하세요."
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "ALB가 배포될 퍼블릭 서브넷 ID 목록"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "ECS Task가 배포될 프라이빗 서브넷 ID 목록"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# 애플리케이션 컨테이너
# -----------------------------------------------------------------------------
variable "app_image" {
  description = "애플리케이션 컨테이너 이미지 URI (예: 123456789.dkr.ecr.ap-northeast-2.amazonaws.com/app:latest)"
  type        = string
}

variable "app_port" {
  description = "애플리케이션이 리스닝하는 포트 번호"
  type        = number
  default     = 8080
}

# -----------------------------------------------------------------------------
# ECS 서비스 스케일링
# -----------------------------------------------------------------------------
variable "desired_count" {
  description = "ECS Service의 원하는 Task 실행 수"
  type        = number
  default     = 2
}

variable "min_count" {
  description = "Auto Scaling 최소 Task 수"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Auto Scaling 최대 Task 수"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# Task Definition 리소스 할당
#
# App Container: CPU 512 / Memory 1024
# ADOT Sidecar:  CPU 256 / Memory 512
# 합계: CPU 768 / Memory 1536 → Task 레벨: CPU 1024 / Memory 2048로 여유 확보
# -----------------------------------------------------------------------------
variable "task_cpu" {
  description = "ECS Task 전체 CPU 단위 (1 vCPU = 1024 units)"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "ECS Task 전체 메모리 (MiB)"
  type        = number
  default     = 2048
}

# -----------------------------------------------------------------------------
# 관측가능성 연동 (observability 모듈 출력값에서 주입)
# -----------------------------------------------------------------------------
variable "amp_workspace_id" {
  description = "AMP Workspace ID (ADOT 환경변수 주입에 사용)"
  type        = string
  default     = ""
}

variable "adot_task_role_arn" {
  description = "ADOT 권한이 포함된 ECS Task Role ARN (observability 모듈에서 생성)"
  type        = string
}

# task_execution_role_arn은 이 모듈(iam.tf)에서 직접 생성합니다.
# 외부에서 주입받지 않으며, task-definition.tf에서 aws_iam_role.task_execution.arn으로 참조합니다.

variable "tags" {
  description = "모든 리소스에 공통으로 적용할 태그 맵"
  type        = map(string)
  default     = {}
}
