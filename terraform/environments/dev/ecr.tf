# =============================================================================
# ECR Repository — svc-mypage
#
# ECS Task Definition의 app_image가 이 레포지토리를 참조합니다.
# GitHub Actions에서 이미지를 빌드하고 push합니다.
# =============================================================================

resource "aws_ecr_repository" "app" {
  name                 = "codecaine-python-mypage"
  image_tag_mutability = "MUTABLE" # :latest 태그 덮어쓰기 허용

  image_scanning_configuration {
    scan_on_push = true # 푸시 시 취약점 스캔
  }

  tags = merge(local.common_tags, {
    Name = "codecaine-python-mypage"
  })
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "sha- 태그 이미지 최근 10개만 유지"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "untagged 이미지 1일 후 삭제"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
