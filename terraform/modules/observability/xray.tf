# =============================================================================
# X-Ray 샘플링 규칙
#
# X-Ray는 완전한 Tail-based sampling(결과를 본 후 샘플링 결정)을 지원하지 않습니다.
# 대신 Head-based sampling(요청 시작 시 결정)이지만, 규칙 조합으로 목표에 근접합니다.
#
# 구현 전략:
#   - 에러 규칙: HTTP 메서드/URL 무관, fixed_rate = 1.0(100%) — 단, X-Ray는
#     응답 코드 기준 샘플링을 규칙 레벨에서 직접 지원하지 않음.
#     [실제 에러 100% 수집 방법]: OTel SDK에서 에러 발생 시 span에 error=true를
#     설정하고, ADOT에서 해당 span을 100% 전송하도록 processor 구성. (Phase 2에서 구현)
#     현재 X-Ray 규칙은 URL 패턴별 샘플링 비율로 근사 구현합니다.
#
# 우선순위(priority): 낮은 숫자가 먼저 매칭됩니다 (1이 최우선).
# 기본 규칙(Default)은 10000으로 최하위입니다.
# =============================================================================

# -----------------------------------------------------------------------------
# 규칙 1: 추천 API 전용 (priority: 100)
#
# /api/v1/recommend* 엔드포인트는 알고리즘 분석을 위해 더 높은 비율로 수집합니다.
# SLO 목표: P99 < 2s (일반 API보다 느림 — 알고리즘 특성)
# 샘플 비율: 10% (정상 트래픽 기준, 에러는 Phase 2 ADOT 설정으로 100% 수집)
# -----------------------------------------------------------------------------
resource "aws_xray_sampling_rule" "recommendation_api" {
  rule_name      = "${var.project}-${var.environment}-recommendation-api"
  priority       = 100
  version        = 1

  # reservoir_size: 초당 최소 보장 수집 요청 수
  # 트래픽이 적어도 초당 최소 1개의 트레이스는 반드시 수집됩니다.
  reservoir_size = 2

  # fixed_rate: reservoir가 소진된 이후 적용되는 샘플링 비율
  fixed_rate = 0.10 # 10%

  # 매칭 조건 (와일드카드 * 지원)
  service_name   = "${var.project}-${var.environment}"
  service_type   = "*" # 서비스 타입 무관
  host           = "*" # 호스트 무관
  http_method    = "*" # GET/POST 모두 포함
  url_path       = "/api/v1/recommend*" # 추천 API 경로 패턴
  resource_arn   = "*"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 규칙 2: 헬스체크 제외 (priority: 200)
#
# ALB 헬스체크(/health)는 빈번하게 호출되지만 관측 가치가 낮습니다.
# 0% 샘플링으로 X-Ray 비용과 노이즈를 절감합니다.
# -----------------------------------------------------------------------------
resource "aws_xray_sampling_rule" "health_check" {
  rule_name      = "${var.project}-${var.environment}-health-check"
  priority       = 200
  version        = 1

  reservoir_size = 0
  fixed_rate     = 0.00 # 0% — 헬스체크는 수집하지 않음

  service_name = "${var.project}-${var.environment}"
  service_type = "*"
  host         = "*"
  http_method  = "GET"
  url_path     = "/health"
  resource_arn = "*"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 규칙 3: 일반 API — 정상 트래픽 (priority: 500)
#
# 위 규칙에 매칭되지 않는 모든 요청에 적용됩니다.
# 5% 샘플링으로 비용을 제어하면서 충분한 관측성을 확보합니다.
#
# [Tail-based 근사 구현 안내]
# X-Ray의 한계: 응답 코드가 결정되기 전에 샘플링 여부를 결정합니다.
# 에러 100% 수집을 위해서는 다음 두 가지 방법을 함께 사용하세요:
#   방법 A: OTel SDK의 ParentBased(AlwaysOn) Sampler + ADOT tail sampling processor
#           → ADOT이 span 완료 후 에러 여부를 보고 최종 결정 (메모리 ~50MB 추가)
#   방법 B: AWS X-Ray SDK의 CentralizedSampler + 에러 시 force_sampling = true
#           → 앱 코드에서 에러 감지 시 강제 샘플링 지정
# Phase 2에서 방법 A(ADOT tail sampling)를 구현합니다.
# -----------------------------------------------------------------------------
resource "aws_xray_sampling_rule" "general_api" {
  rule_name      = "${var.project}-${var.environment}-general-api"
  priority       = 500
  version        = 1

  # 저트래픽에서도 트레이스 확보: 초당 최소 1개 보장
  reservoir_size = 1

  fixed_rate = 0.05 # 5%

  service_name = "${var.project}-${var.environment}"
  service_type = "*"
  host         = "*"
  http_method  = "*"
  url_path     = "*"
  resource_arn = "*"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 기본 규칙 (Default Rule) 안내
#
# X-Ray에는 삭제할 수 없는 기본 규칙(Default)이 있습니다:
#   - priority: 10000
#   - reservoir_size: 1
#   - fixed_rate: 0.05 (5%)
#
# 위 규칙들이 매칭되지 않는 요청(다른 서비스에서 오는 트레이스 등)은
# Default 규칙이 적용됩니다.
# Default 규칙을 변경하려면 AWS Console 또는 CLI에서 수정하거나,
# aws_xray_sampling_rule 리소스 이름을 "Default"로 생성하세요.
# -----------------------------------------------------------------------------
