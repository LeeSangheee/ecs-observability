# =============================================================================
# dev 환경 — 변수 값 설정
#
# [보안 주의사항]
# 이 파일에 민감한 정보(비밀번호, API 키, 토큰 등)를 절대 넣지 마세요.
# 이 파일은 Git에 커밋됩니다.
#
# 민감한 값은 다음 방법으로 주입하세요:
#   export TF_VAR_alarm_slack_webhook_url="https://hooks.slack.com/..."
# =============================================================================

region      = "ap-northeast-2"
environment = "dev"
project     = "supplement-rec"

# 실제 앱 이미지 빌드 전 임시 이미지
# Phase 2에서 ECR URI로 교체하세요.
# 예: 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/supplement-rec:latest
app_image = "nginx:latest"

app_port = 8080

# AMP(aps-workspaces) VPC Interface Endpoint 생성 여부
# 서울 리전(ap-northeast-2) 지원 확인 명령어:
#   aws ec2 describe-vpc-endpoint-services \
#     --filters "Name=service-name,Values=com.amazonaws.ap-northeast-2.aps-workspaces" \
#     --region ap-northeast-2 \
#     --query "ServiceNames"
# 지원 시 true로 변경하세요.
create_amp_endpoint = false

# CloudWatch Alarm 이메일 수신 주소
# 설정 시 이메일 Subscription 확인 링크를 클릭해야 활성화됩니다.
alarm_email = ""

# Slack Webhook URL은 이 파일에 직접 넣지 마세요.
# 환경변수로 주입하세요: export TF_VAR_alarm_slack_webhook_url="https://..."
# alarm_slack_webhook_url은 Phase 3에서 구현됩니다.
