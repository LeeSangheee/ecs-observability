# =============================================================================
# ecs 모듈 — IAM Role 정의
#
# ECS에는 두 가지 IAM Role이 필요합니다:
#
# 1. Task Execution Role (ecsTaskExecutionRole 패턴)
#    - ECS 에이전트가 사용 (컨테이너 런타임 환경)
#    - ECR에서 이미지 Pull
#    - CloudWatch Logs에 로그 그룹 생성 및 스트림 쓰기
#    - Secrets Manager / SSM Parameter Store에서 환경변수 주입
#
# 2. Task Role (애플리케이션이 사용)
#    - 컨테이너 내부 코드가 AWS API를 호출할 때 사용하는 권한
#    - ADOT Sidecar가 X-Ray, AMP, CloudWatch Logs에 데이터를 쓸 때 필요
#    - 이 프로젝트에서는 observability 모듈이 별도로 생성한 ADOT Task Role을 사용
# =============================================================================

# -----------------------------------------------------------------------------
# Task Execution Role
#
# ECS 에이전트(Fargate 플랫폼)가 컨테이너를 시작하기 위해 필요한 권한입니다.
# 애플리케이션 코드와는 무관합니다.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "task_execution" {
  name        = "${var.project}-${var.environment}-ecs-task-execution-role"
  description = "ECS Task Execution Role — ECR Pull, CloudWatch Logs 쓰기, SSM 읽기"

  # ECS Tasks 서비스가 이 Role을 Assume할 수 있도록 허용
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

# AWS 관리형 정책: ECR Pull + CloudWatch Logs 기본 권한
resource "aws_iam_role_policy_attachment" "task_execution_basic" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# SSM Parameter Store 읽기 권한
# ADOT 설정 파일(collector-config.yaml)을 SSM에서 주입하는 Phase 2에서 활용됩니다.
resource "aws_iam_role_policy" "task_execution_ssm" {
  name = "${var.project}-${var.environment}-task-execution-ssm"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMParameterReadForAdotConfig"
        Effect = "Allow"
        Action = [
          # GetParameters: 다수의 파라미터를 한 번에 조회
          "ssm:GetParameters",
          # GetParameter: 단일 파라미터 조회
          "ssm:GetParameter"
        ]
        # 보안: 특정 경로 하위의 파라미터만 접근 허용
        # Phase 2에서 /ecs/{project}/{environment}/adot-config 경로 사용 예정
        Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.project}/${var.environment}/*"
      }
    ]
  })
}
