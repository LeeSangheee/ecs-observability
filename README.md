# ECS Fargate 기반 AWS Native Observability 기획서

## 1. 프로젝트 개요

영양제 추천 서비스(ECS Fargate)에 대해 **AWS 관리형 서비스**로 관측가능성(Observability) 환경을 구축합니다.
단순 지표 수집이 아닌, **의미 있는 비즈니스/운영 지표**를 관측하는 것이 핵심 목표입니다.

### 기술 스택

| 구성요소 | 기술 |
|---------|------|
| 로그 | CloudWatch Logs |
| 메트릭 | AMP (Amazon Managed Prometheus) |
| 트레이스 | AWS X-Ray |
| 시각화 | AMG (Amazon Managed Grafana) |
| 수집기 | ADOT Sidecar (ECS Task 내) |
| IaC | Terraform |
| CI/CD | GitHub Actions |

---

## 2. 아키텍처

### 전체 데이터 흐름

```
사용자
  │
  ▼
API Gateway
  │
  ▼
ALB
  │
  ▼
┌─────────────────────────────────────┐
│  ECS Task (Fargate)                 │
│                                     │
│  ┌──────────────┐  ┌─────────────┐  │
│  │  App Container│  │ADOT Sidecar │  │
│  │  (추천 서비스) │──▶│  Collector  │  │
│  │  OTel SDK 계측│  │             │  │
│  └──────────────┘  └──────┬──────┘  │
└─────────────────────────── ┼ ───────┘
                             │
               ┌─────────────┼─────────────┐
               ▼             ▼             ▼
        CloudWatch Logs    AMP           X-Ray
        (로그)           (메트릭)       (트레이스)
               └─────────────┼─────────────┘
                             ▼
                      AMG (Grafana)
                       통합 시각화
```

### 네트워크 구성

```
VPC (10.0.0.0/16)
├── Public Subnet
│   └── ALB, NAT Gateway
├── Private Subnet
│   └── ECS Fargate Tasks (App + ADOT Sidecar)
└── VPC Endpoints (PrivateLink — NAT 비용 절감 + 보안)
    ├── com.amazonaws.{region}.xray
    ├── com.amazonaws.{region}.logs
    ├── com.amazonaws.{region}.aps-workspaces
    └── com.amazonaws.{region}.monitoring
```

> **주의**: AMP VPC Endpoint(`aps-workspaces`)는 리전별로 가용 여부가 다릅니다.
> `ap-northeast-2`(서울) 지원 여부를 사전 확인해야 합니다. 미지원 시 NAT Gateway 경유.

### 영양제 추천 서비스 의존 관계

```
Client → API Gateway → ALB → ECS Fargate (추천 서비스)
                                      │
                       ┌──────────────┼──────────────┐
                       ▼              ▼              ▼
               사용자 프로필       추천 엔진        결과 캐시
                (RDS)             처리             (ElastiCache)
                                      │
                                      ▼
                                 DynamoDB
                               (추천 이력 저장)
```

---

## 3. ADOT Collector 파이프라인 설계

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317    # App → ADOT (gRPC, localhost 통신)
      http:
        endpoint: 0.0.0.0:4318    # 폴백용

  awsecscontainermetrics:          # ECS Task CPU/메모리 자동 수집
    collection_interval: 20s

processors:
  memory_limiter:                  # 사이드카 OOM 방지
    check_interval: 1s
    limit_mib: 200
    spike_limit_mib: 50

  batch:                           # 배치 전송으로 비용 절감
    timeout: 5s
    send_batch_size: 512

  resource:                        # 서비스 식별 속성 추가
    attributes:
      - key: service.name
        value: "supplement-recommendation"
        action: upsert
      - key: deployment.environment
        value: "production"
        action: upsert

exporters:
  prometheusremotewrite:           # 메트릭 → AMP
    endpoint: "https://aps-workspaces.{region}.amazonaws.com/..."
    auth:
      authenticator: sigv4auth

  awsxray:                         # 트레이스 → X-Ray
    region: ap-northeast-2

  awscloudwatchlogs:               # 로그 → CloudWatch Logs
    log_group_name: "/ecs/supplement-recommendation"
    region: ap-northeast-2

service:
  pipelines:
    metrics:
      receivers: [otlp, awsecscontainermetrics]
      processors: [memory_limiter, batch, resource]
      exporters: [prometheusremotewrite]
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [awsxray]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [awscloudwatchlogs]
```

---

## 4. 의미 있는 지표 설계

### 4.1 Golden Signals

#### Latency (응답 시간)
- P50 / P95 / P99 응답시간 — 엔드포인트별
- 추천 API vs 일반 API 레이턴시 비교
- E2E 레이턴시 분해: 프로필 조회 → 전처리 → 알고리즘 → 필터링 → 응답

#### Traffic (트래픽)
- RPS (초당 요청 수)
- 엔드포인트별 트래픽 비율
- 동시 활성 요청 수

#### Errors (에러)
- 전체 에러율 (5xx 비율 %)
- HTTP 상태코드별 분포
- 비즈니스 로직 에러 분류 (추천 실패, 프로필 미존재 등)

#### Saturation (포화도)
- CPU 사용률 vs 응답시간 상관관계 오버레이 차트
- 메모리 사용률 트렌드
- 동시 접속자 수 vs 리소스 사용률

### 4.2 SLI/SLO

| SLI | 정의 | SLO 목표 |
|-----|------|---------|
| 가용성 | 성공 응답(2xx/3xx) / 전체 요청 | **99.9%** (월간) |
| 레이턴시 — 일반 API | P99 < 200ms 비율 | **99%** |
| 레이턴시 — 추천 API | P99 < 2s 비율 | **95%** (알고리즘 특성 반영) |
| 추천 정확도 | 추천 결과 반환 성공 / 추천 요청 | **99.5%** |

**Error Budget**: 월 100만 요청 기준, 가용성 99.9% → 허용 에러 1,000건 (일 ~33건)

### 4.3 비즈니스 메트릭 (커스텀 계측 필요)

| 메트릭명 | 타입 | 라벨 | 의미 |
|---------|------|------|------|
| `recommendation_request_total` | Counter | `algorithm_type`, `user_segment` | 추천 요청 수 |
| `recommendation_duration_seconds` | Histogram | `algorithm_type`, `cache_hit` | 추천 처리 시간 |
| `recommendation_cache_hit_total` | Counter | `cache_type` | 캐시 히트 수 |
| `recommendation_cache_miss_total` | Counter | `cache_type` | 캐시 미스 수 |
| `recommendation_error_total` | Counter | `error_type` | 추천 실패 분류 |
| `user_profile_fetch_duration_seconds` | Histogram | `source` (rds/cache) | 프로필 조회 시간 |

> **카디널리티 주의**: `user_id`를 메트릭 라벨로 사용하면 시계열 폭증 → AMP 비용 급증.
> 사용자 세그먼트(연령대, 성별 등)로 그룹화하거나 exemplar로 전달할 것.

### 4.4 알림 규칙

| 알림 | 조건 | 심각도 | 채널 |
|------|------|--------|------|
| 높은 에러율 | 5xx 비율 > 1% (5분) | Critical | Slack + PagerDuty |
| 추천 API 느림 | P95 > 3s (5분) | Warning | Slack |
| Error Budget 소진 | 잔량 < 30% | Warning | Slack + Email |
| Error Budget 위험 | 잔량 < 10% | Critical | Slack + PagerDuty |
| ECS Task 비정상 | Running < Desired (3분) | Critical | Slack |
| CPU 과부하 | CPU > 80% (10분) | Warning | Slack |
| 캐시 히트율 하락 | 히트율 < 70% (15분) | Info | Slack |

### 4.5 X-Ray 샘플링 전략

| 옵션 | 방식 | 장점 | 단점 |
|------|------|------|------|
| A. 고정 5% | 모든 요청의 5% | 단순, 예측 가능한 비용 | 드문 에러 트레이스 누락 가능 |
| B. Reservoir + Rate | 초당 1개 보장 + 나머지 5% | 저트래픽에서도 트레이스 확보 | 설정 복잡도 증가 |
| **C. Tail-based (권장)** | 에러/고레이턴시 100% + 정상 5% | 장애 분석 트레이스 유실 없음 | 사이드카 메모리 ~50MB 추가 |

---

## 5. 디렉토리 구조

```
ecs-observability/
├── README.md                        ← 이 파일
├── docs/
│   └── otel-flow.html
├── terraform/
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf              # dev 환경 모듈 조합
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf           # S3 + DynamoDB state
│   │   └── prod/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── terraform.tfvars
│   │       └── backend.tf
│   └── modules/
│       ├── networking/              # VPC, Subnet, VPC Endpoints
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── ecs/                     # Cluster, Task Def, Service, ALB
│       │   ├── main.tf
│       │   ├── task-definition.tf   # App + ADOT Sidecar
│       │   ├── iam.tf               # Task Role, Execution Role
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── observability/           # AMP, X-Ray, CloudWatch, AMG, Alarms
│       │   ├── amp.tf
│       │   ├── xray.tf
│       │   ├── cloudwatch.tf
│       │   ├── amg.tf
│       │   ├── alarms.tf
│       │   ├── iam.tf               # ADOT IAM Role
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── adot-config/
│       │   ├── collector-config.yaml
│       │   └── sampling-rules.json
│       └── dashboards/
│           ├── golden-signals.json
│           ├── slo-overview.json
│           ├── business-metrics.json
│           └── infra-correlation.json
├── app/
│   ├── Dockerfile
│   └── src/
└── .github/
    └── workflows/
        ├── terraform-plan.yml
        └── terraform-apply.yml
```

### 모듈 의존 관계

```
networking  →  ecs  →  observability
(최하위)       (중간)       (상위)
```

---

## 6. 구현 로드맵

### Phase 1 — 인프라 기반 (1~2주)

- [ ] VPC + Subnet + VPC Endpoints 구성
- [ ] ECS Cluster + Task Definition (앱 컨테이너 단독)
- [ ] AMP Workspace 생성
- [ ] CloudWatch Log Group 생성
- [ ] IAM Role 구성 (ADOT Task Role — 최소 권한)
- [ ] ADOT 사이드카 Task Definition에 추가 + healthcheck 확인

**ADOT IAM 최소 권한**:
```json
{
  "Statement": [
    { "Action": ["aps:RemoteWrite"], "Resource": "arn:aws:aps:..." },
    { "Action": ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"], "Resource": "*" },
    { "Action": ["logs:CreateLogStream", "logs:PutLogEvents"], "Resource": "arn:aws:logs:...:log-group:/ecs/supplement-recommendation:*" }
  ]
}
```

### Phase 2 — 계측 및 수집 파이프라인 (2~3주)

- [ ] OTel SDK 앱 통합 (auto-instrumentation)
- [ ] 커스텀 비즈니스 메트릭 계측 코드 추가
- [ ] ADOT collector-config.yaml 작성 및 SSM Parameter Store 배포
- [ ] 메트릭 → AMP 전달 확인 (PromQL 쿼리)
- [ ] 로그 → CloudWatch Logs 전달 확인
- [ ] 트레이스 → X-Ray 전달 확인 (서비스 맵)
- [ ] 로그에 Trace ID 포함 확인 (로그-트레이스 연계)

> **ADOT 설정 배포 방식**: SSM Parameter Store 권장.
> 이미지 재빌드 없이 설정 변경 가능. S3 대비 암호화 기본 지원.

### Phase 3 — 대시보드 및 알림 (2주)

- [ ] AMG Workspace 생성 + IAM Identity Center 연동
- [ ] 데이터소스 연결 (AMP, CloudWatch, X-Ray)
- [ ] Golden Signals 대시보드 구축
- [ ] 비즈니스 메트릭 대시보드 구축
- [ ] 인프라 상관관계 대시보드 (CPU/메모리 vs 응답시간 오버레이)
- [ ] SNS → Slack Webhook 알림 연동
- [ ] 알림 규칙 설정 및 테스트

### Phase 4 — SLI/SLO 및 Error Budget (1~2주)

- [ ] AMP Recording Rules로 SLI 메트릭 사전 계산
- [ ] SLO 달성률 대시보드 구축
- [ ] Error Budget 잔량 차트 (30일 rolling window)
- [ ] Error Budget 기반 알림 (30%, 10% 임계값)
- [ ] 주간 SLO 리포트 자동 생성

---

## 7. 예상 월 비용

> 전제: 서울 리전(`ap-northeast-2`), 일 10만 요청, 피크 RPS ~10

| 서비스 | 월 비용 (USD) |
|--------|-------------|
| AMP (메트릭 수집/저장) | ~$4.56 |
| CloudWatch Logs (수집/저장/쿼리) | ~$4.05 |
| X-Ray (트레이스 기록/조회) | ~$1.00 |
| AMG (Editor 2명, Viewer 3명) | ~$33.00 |
| VPC Endpoints (3개 × 2AZ) | ~$60.48 |
| ADOT Sidecar 추가 Fargate 리소스 | ~$12.00 |
| **합계** | **~$115** |

### 비용 최적화 포인트

1. **VPC Endpoint vs NAT Gateway**: 초기 트래픽이 월 10GB 이하라면 NAT Gateway($45/월)가 더 저렴할 수 있음. 트래픽 증가 후 전환 고려.
2. **CloudWatch Logs 보관 기간**: 30일 제한 후 S3 Export → 저장 비용 1/10 절감.
3. **X-Ray 샘플링률**: 5% → 1%로 낮추면 트레이스 비용 80% 절감. 단, 저빈도 에러 트레이스 누락 위험.

---

## 8. 보안 및 컴플라이언스

영양제 추천 서비스는 **사용자 건강 데이터**를 처리하므로 다음을 반드시 준수합니다.

| 항목 | 조치 |
|------|------|
| 로그 PII 필터링 | ADOT `attributes/delete` processor로 민감 필드 마스킹 |
| 전송 암호화 | VPC Endpoint 사용 시 TLS 자동 적용 |
| 저장 암호화 | CloudWatch Logs KMS 암호화 |
| 접근 제어 | AMG는 IAM Identity Center SSO만 허용 |
| 감사 로그 | CloudTrail로 AMP/X-Ray/AMG API 호출 기록 |

> **중요**: OTel SDK auto-instrumentation은 HTTP 헤더·쿼리 파라미터를 span attribute에 자동 포함합니다.
> 건강 설문 응답이 query parameter로 전달되는 경우, 트레이스에 민감 정보가 기록될 수 있습니다.
> ADOT Processor에서 `health_survey`, `birth_date` 등의 패턴을 삭제하거나 해시 처리해야 합니다.

---

## 9. 잠재적 리스크

| 리스크 | 완화 방안 |
|--------|----------|
| ADOT 사이드카 OOM | `memory_limiter` processor + 사이드카 512MB 할당 |
| AMP Remote Write 실패 → 메트릭 유실 | ADOT retry 기본 5회 + Remote Write 실패 알림 별도 설정 |
| X-Ray 트레이스 폭증 → 비용 급증 | Tail-based sampling + 샘플링 규칙 상한 설정 |
| 로그에 민감 정보 유출 | ADOT attributes processor 필터링 + 배포 전 로그 샘플 검토 |
| AMG VPC Endpoint 서울 리전 미지원 | 사전 검증 + NAT Gateway 폴백 플랜 |
| AMG 전제조건 미충족 | IAM Identity Center(SSO) 사전 활성화 필요 (Terraform 자동화 어려움) |
