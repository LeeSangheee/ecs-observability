# =============================================================================
# GitHub Actions OIDC 기반 배포용 IAM 설정
#
# GitHub Actions에서 AWS 자격증명을 시크릿으로 관리하지 않고
# OIDC를 통해 임시 자격증명을 발급받습니다.
#
# 워크플로우에서 사용하는 시크릿:
#   AWS_DEPLOY_ROLE_ARN = aws_iam_role.github_actions.arn (terraform output으로 확인)
# =============================================================================

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub Actions OIDC 인증서 지문 (GitHub에서 공식 제공)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = local.common_tags
}

resource "aws_iam_role" "github_actions" {
  name        = "${var.project}-${var.environment}-github-actions"
  description = "GitHub Actions OIDC role for svc-mypage CI/CD"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # main 브랜치 push + PR 모두 허용
            "token.actions.githubusercontent.com:sub" = "repo:ACS-Nutrients/codecaine-python-mypage:*"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "github_actions" {
  name = "ecr-push-ecs-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid    = "ECSUpdate"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
        ]
        Resource = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${module.ecs.cluster_name}/${module.ecs.service_name}"
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "GitHub Actions에서 AWS_DEPLOY_ROLE_ARN 시크릿에 등록할 IAM Role ARN"
  value       = aws_iam_role.github_actions.arn
}
