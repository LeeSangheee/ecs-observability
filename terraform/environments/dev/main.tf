# =============================================================================
# dev 환경 — 모듈 조합
#
# 모듈 의존 관계 (단방향):
#   networking  →  ecs
#       ↓
#   observability (IAM + AMP + CloudWatch + X-Ray 생성)
#       ↓
#   [alarms] — environments/dev/main.tf에서 직접 리소스로 생성
#
# [순환 참조 해결 방법]
# 문제: ecs 모듈이 observability(adot_task_role_arn)를 참조하고,
#       observability 모듈의 alarms가 ecs(alb_arn_suffix 등)를 참조하면
#       Terraform에서 순환 참조(Cycle) 오류가 발생합니다.
#
# 해결: CloudWatch Alarms는 observability 모듈 내 alarms.tf가 아닌
#       이 파일(environments/dev/main.tf)에서 직접 aws_cloudwatch_metric_alarm
#       리소스로 생성합니다.
#       - networking + observability(IAM/AMP/CW/XRay)는 ecs와 독립
#       - ecs는 observability.adot_task_role_arn만 참조 (단방향)
#       - alarms는 ecs + observability 둘 다 참조하지만, 모듈 외부이므로 순환 없음
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# =============================================================================
# 공통 태그 — 모든 AWS 리소스에 자동으로 적용됩니다.
# =============================================================================
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
    Repository  = "ecs-observability"
  }
}

# =============================================================================
# Module 1: Networking
#
# 의존하는 모듈: 없음 (최하위 레이어)
# 출력: vpc_id, public_subnet_ids, private_subnet_ids
# =============================================================================
module "networking" {
  source = "../../modules/networking"

  project     = var.project
  environment = var.environment
  region      = var.region

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_azs    = ["ap-northeast-2a", "ap-northeast-2c"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  private_subnet_azs   = ["ap-northeast-2a", "ap-northeast-2c"]

  create_amp_endpoint = var.create_amp_endpoint

  tags = local.common_tags
}

# =============================================================================
# Module 2: Observability (IAM + AMP + CloudWatch Log Groups + X-Ray + SNS)
#
# 의존하는 모듈: 없음 (networking과도 독립)
# 출력: adot_task_role_arn, amp_workspace_id, alarm_sns_topic_arn
#
# [알람(CloudWatch Metric Alarms)은 environments/dev/alarms.tf에서 생성합니다]
# Alarms가 ECS 출력값(ALB ARN suffix)을 참조하는 동시에
# observability 출력값(SNS Topic ARN)도 참조하기 때문입니다.
# 순환 참조 방지를 위해 alarms는 모듈 외부에서 생성합니다.
# =============================================================================
module "observability" {
  source = "../../modules/observability"

  project     = var.project
  environment = var.environment
  region      = var.region

  alarm_email             = var.alarm_email
  alarm_slack_webhook_url = var.alarm_slack_webhook_url

  log_retention_days = 30

  tags = local.common_tags
}

# =============================================================================
# Module 3: ECS
#
# 의존하는 모듈: networking, observability
# 의존 이유:
#   - networking: VPC ID, Subnet ID 필요
#   - observability: ADOT Task Role ARN 필요 (Task Definition에 주입)
# =============================================================================
module "ecs" {
  source = "../../modules/ecs"

  project     = var.project
  environment = var.environment
  region      = var.region

  # networking 모듈 출력값
  vpc_id             = module.networking.vpc_id
  vpc_cidr           = module.networking.vpc_cidr
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids

  # 애플리케이션 설정
  app_image = var.app_image
  app_port  = var.app_port

  # ECS 서비스 스케일링
  desired_count = 2
  min_count     = 1
  max_count     = 4

  # observability 모듈 출력값
  # ADOT Sidecar의 Task Role ARN (X-Ray, AMP, CloudWatch Logs 권한 포함)
  amp_workspace_id    = module.observability.amp_workspace_id
  adot_task_role_arn  = module.observability.adot_task_role_arn
  adot_config_ssm_arn = module.observability.adot_config_ssm_arn

  tags = local.common_tags
}

# =============================================================================
# 출력값 — terraform output 명령으로 확인 가능
# =============================================================================

output "alb_url" {
  description = "애플리케이션 접속 URL (ALB DNS)"
  value       = "http://${module.ecs.alb_dns_name}"
}

output "amp_endpoint" {
  description = "AMP Remote Write Endpoint (ADOT collector-config.yaml에서 사용)"
  value       = module.observability.amp_workspace_endpoint
}

output "amp_workspace_id" {
  description = "AMP Workspace ID"
  value       = module.observability.amp_workspace_id
}

output "adot_task_role_arn" {
  description = "ADOT Task Role ARN"
  value       = module.observability.adot_task_role_arn
}

output "alarm_sns_topic_arn" {
  description = "알람 SNS Topic ARN"
  value       = module.observability.alarm_sns_topic_arn
}

output "nat_public_ips" {
  description = "NAT Gateway 퍼블릭 IP (외부 서비스 허용 목록 등록용)"
  value       = module.networking.nat_public_ips
}

output "ecs_cluster_name" {
  description = "ECS Cluster 이름"
  value       = module.ecs.cluster_name
}

output "task_definition_arn" {
  description = "ECS Task Definition ARN"
  value       = module.ecs.task_definition_arn
}
