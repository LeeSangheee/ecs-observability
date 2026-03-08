# =============================================================================
# Terraform Backend 설정 — S3 + DynamoDB
#
# [사용 전 필수 사전 작업]
# 아래 주석을 해제하기 전에 S3 버킷과 DynamoDB 테이블을 먼저 생성해야 합니다.
# Terraform은 자신의 state 파일을 저장할 곳이 없으면 초기화 자체가 불가능합니다.
#
# 방법 1: AWS Console에서 수동 생성
# 방법 2: 별도의 bootstrap Terraform 코드로 생성 (terraform/bootstrap/ 디렉토리)
#
# S3 버킷 생성 예시 (AWS CLI):
#   aws s3api create-bucket \
#     --bucket YOUR-TERRAFORM-STATE-BUCKET \
#     --region ap-northeast-2 \
#     --create-bucket-configuration LocationConstraint=ap-northeast-2
#
#   aws s3api put-bucket-versioning \
#     --bucket YOUR-TERRAFORM-STATE-BUCKET \
#     --versioning-configuration Status=Enabled
#
#   aws s3api put-bucket-server-side-encryption-configuration \
#     --bucket YOUR-TERRAFORM-STATE-BUCKET \
#     --server-side-encryption-configuration '{
#       "Rules": [{
#         "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
#       }]
#     }'
#
# DynamoDB 테이블 생성 예시 (AWS CLI):
#   aws dynamodb create-table \
#     --table-name YOUR-TERRAFORM-STATE-LOCK-TABLE \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region ap-northeast-2
#
# 생성 완료 후 아래 backend 블록의 주석을 해제하고 값을 입력하세요.
# =============================================================================

# terraform {
#   backend "s3" {
#     # 사전 생성한 S3 버킷 이름으로 교체하세요
#     bucket = "YOUR-TERRAFORM-STATE-BUCKET"
#
#     # state 파일 경로 (환경별로 분리)
#     key    = "ecs-observability/dev/terraform.tfstate"
#
#     region = "ap-northeast-2"
#
#     # 사전 생성한 DynamoDB 테이블 이름으로 교체하세요
#     # State Locking: 여러 사람이 동시에 apply하는 것을 방지합니다.
#     dynamodb_table = "YOUR-TERRAFORM-STATE-LOCK-TABLE"
#
#     # state 파일 암호화 (S3 버킷 수준 암호화와 별개로 추가 레이어)
#     encrypt = true
#   }
# }

# =============================================================================
# [현재 설정] 로컬 Backend
#
# backend.tf가 비어있으면 Terraform은 로컬 파일(terraform.tfstate)에
# state를 저장합니다. 개발 초기 단계나 개인 작업 시 사용 가능합니다.
#
# 주의: 로컬 state는 팀 협업이나 CI/CD와 함께 사용할 수 없습니다.
# 실제 운영에서는 반드시 S3 Backend를 사용하세요.
# =============================================================================
