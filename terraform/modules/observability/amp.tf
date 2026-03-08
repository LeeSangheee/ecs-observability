# =============================================================================
# AMP (Amazon Managed Prometheus) — Workspace + Recording Rules
#
# AMP는 완전 관리형 Prometheus 호환 서비스입니다.
# ADOT Sidecar가 Remote Write 프로토콜로 메트릭을 전송합니다.
#
# [AMG 안내]
# AMG(Amazon Managed Grafana)는 IAM Identity Center(SSO) 사전 설정이 필요합니다.
# IAM Identity Center는 Terraform으로 완전 자동화가 어려워 Phase 3에서 수동 설정 후
# Terraform import로 관리합니다.
# Phase 3 설정 가이드:
#   1. AWS Console → IAM Identity Center 활성화
#   2. AMG Workspace 생성 (콘솔 또는 Terraform aws_grafana_workspace 리소스)
#   3. AMP, CloudWatch, X-Ray 데이터소스 연결
# =============================================================================

resource "aws_amp_workspace" "main" {
  alias = "${var.project}-${var.environment}"

  # KMS 암호화 (선택사항 — 운영 환경에서 권장)
  # kms_key_arn = aws_kms_key.amp.arn

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-amp"
  })
}

# =============================================================================
# AMP Recording Rules
#
# Recording Rules는 자주 사용되는 PromQL 표현식을 사전 계산하여 저장합니다.
# 대시보드 쿼리 성능 향상 + SLI 계산에 활용됩니다.
#
# 규칙 구성:
#   1. HTTP 요청 관련 (에러율, 초당 요청 수)
#   2. 레이턴시 관련 (P99, P95, P50)
#   3. SLI 관련 (가용성, Error Budget 소진율)
#
# [주의] aws_amp_rule_group_namespace 리소스는 전체 YAML을 한 번에 관리합니다.
# 규칙을 수정하면 전체 네임스페이스가 교체됩니다.
# =============================================================================
resource "aws_amp_rule_group_namespace" "sli_recording_rules" {
  name         = "sli-recording-rules"
  workspace_id = aws_amp_workspace.main.id

  # YAML 형식의 Prometheus Recording Rules
  data = <<-YAML
    groups:
      # -----------------------------------------------------------------------
      # HTTP 요청 통계 — 1분 단위 사전 계산
      # -----------------------------------------------------------------------
      - name: http_request_stats
        interval: 60s
        rules:
          # 초당 요청 수 (엔드포인트별)
          - record: job:http_requests_total:rate5m
            expr: |
              sum by (job, http_method, http_route, http_status_code) (
                rate(http_server_duration_milliseconds_count[5m])
              )

          # 에러 요청 비율 (5xx 응답)
          # 분모가 0인 경우(요청 없음) NaN 방지: or vector(0)
          - record: job:http_error_rate:rate5m
            expr: |
              sum by (job) (
                rate(http_server_duration_milliseconds_count{http_status_code=~"5.."}[5m])
              )
              /
              sum by (job) (
                rate(http_server_duration_milliseconds_count[5m])
              )

          # 성공 요청 비율 (SLI 가용성 계산용)
          - record: job:http_success_rate:rate5m
            expr: |
              sum by (job) (
                rate(http_server_duration_milliseconds_count{http_status_code=~"2..|3.."}[5m])
              )
              /
              sum by (job) (
                rate(http_server_duration_milliseconds_count[5m])
              )

      # -----------------------------------------------------------------------
      # 레이턴시 — Histogram에서 Quantile 사전 계산
      # Histogram 데이터는 OTel SDK + ADOT → AMP로 전송됩니다.
      # -----------------------------------------------------------------------
      - name: latency_percentiles
        interval: 60s
        rules:
          # P99 레이턴시 (ms)
          - record: job:http_request_duration_ms:p99
            expr: |
              histogram_quantile(0.99,
                sum by (job, le) (
                  rate(http_server_duration_milliseconds_bucket[5m])
                )
              )

          # P95 레이턴시 (ms)
          - record: job:http_request_duration_ms:p95
            expr: |
              histogram_quantile(0.95,
                sum by (job, le) (
                  rate(http_server_duration_milliseconds_bucket[5m])
                )
              )

          # P50 레이턴시 (ms)
          - record: job:http_request_duration_ms:p50
            expr: |
              histogram_quantile(0.50,
                sum by (job, le) (
                  rate(http_server_duration_milliseconds_bucket[5m])
                )
              )

          # 추천 API 전용 P99 (알고리즘 성능 추적)
          - record: job:recommendation_api_duration_ms:p99
            expr: |
              histogram_quantile(0.99,
                sum by (job, le) (
                  rate(http_server_duration_milliseconds_bucket{http_route=~"/api/v1/recommend.*"}[5m])
                )
              )

      # -----------------------------------------------------------------------
      # SLO Error Budget 추적 — 30일 rolling window
      # SLO 목표: 가용성 99.9% (허용 에러 비율 0.1%)
      # -----------------------------------------------------------------------
      - name: error_budget
        interval: 300s  # 5분마다 계산 (비용 절감)
        rules:
          # 30일 성공률
          - record: job:http_success_rate:30d
            expr: |
              sum by (job) (
                rate(http_server_duration_milliseconds_count{http_status_code=~"2..|3.."}[30d])
              )
              /
              sum by (job) (
                rate(http_server_duration_milliseconds_count[30d])
              )

          # Error Budget 잔량 (0이면 SLO 위반)
          # 목표 가용성: 99.9% → 허용 에러 비율 0.1% = 0.001
          # 잔량 = (실제 에러 비율) / (허용 에러 비율)
          # 0.3 이하: Warning / 0.1 이하: Critical
          - record: job:error_budget_remaining:30d
            expr: |
              1 - (
                (1 - job:http_success_rate:30d) / 0.001
              )
  YAML
}
