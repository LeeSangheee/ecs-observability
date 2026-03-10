# ECS Fargate 기반 AWS Native Observability

## 1. 프로젝트 개요

영양제 추천 서비스(`codecaine-python-mypage`) ECS Fargate 위에 **AWS 관리형 서비스**로 관측가능성(Observability) 환경을 구축합니다.
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
| CI/CD | GitHub Actions (OIDC) |

---

## 2. 아키텍처

### 전체 데이터 흐름

```
사용자
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
│  │  (mypage)     │──▶│  Collector  │  │
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
└── VPC Endpoints (PrivateLink)
    ├── ecr.api / ecr.dkr
    ├── logs
    ├── monitoring
    ├── xray
    └── s3
```

### ADOT Collector 파이프라인

```
App (OTel SDK)
  │ OTLP gRPC (localhost:4317)
  ▼
ADOT Sidecar
  ├── metrics → AMP (prometheusremotewrite + SigV4)
  ├── traces  → X-Ray (awsxray)
  └── logs    → CloudWatch Logs (awscloudwatchlogs)
```

ADOT 설정은 SSM Parameter Store(`/supplement-rec/dev/adot-config`)에서 관리합니다.
이미지 재빌드 없이 SSM 값만 수정 후 ECS 재배포로 설정 변경이 가능합니다.

---

## 3. 디렉토리 구조

```
ecs-observability/
├── terraform/
│   ├── environments/
│   │   └── dev/
│   │       ├── main.tf              # 모듈 조합 (networking → observability → ecs)
│   │       ├── variables.tf
│   │       ├── terraform.tfvars
│   │       ├── backend.tf
│   │       ├── alarms.tf            # CloudWatch Alarms (순환참조 방지용)
│   │       ├── ecr.tf               # ECR 레포지토리
│   │       └── github-actions.tf    # OIDC IAM Role
│   └── modules/
│       ├── networking/              # VPC, Subnet, NAT GW, VPC Endpoints, ALB
│       ├── ecs/                     # ECS Cluster, Service, Task Definition, IAM
│       └── observability/
│           ├── amp.tf               # AMP Workspace + Recording Rules
│           ├── cloudwatch.tf        # Log Groups + Metric Filters
│           ├── grafana.tf           # AMG Workspace + IAM Role
│           ├── iam.tf               # ADOT Task Role
│           ├── sns.tf               # SNS Topic
│           ├── ssm.tf               # ADOT Config (SSM Parameter Store)
│           ├── xray.tf              # X-Ray Sampling Rules
│           ├── dashboards/
│           │   └── golden-signals.json  # Golden Signals 대시보드
└── .gitignore
```

---

## 4. 구현 현황

### Phase 1 — 인프라 기반 ✅

- [x] VPC + Subnet + NAT Gateway + VPC Endpoints
- [x] ALB + Target Group + Listener
- [x] ECS Cluster + Task Definition (App + ADOT Sidecar)
- [x] AMP Workspace 생성
- [x] CloudWatch Log Groups
- [x] IAM Role (ADOT Task Role, Task Execution Role)
- [x] X-Ray Sampling Rules
- [x] SNS Topic + CloudWatch Alarms
- [x] ADOT 설정 SSM Parameter Store 저장

### Phase 2 — 앱 계측 + CI/CD ✅

- [x] OTel SDK 앱 통합 (FastAPI, SQLAlchemy, HTTPX 자동 계측)
- [x] ECR 레포지토리 생성 (`codecaine-python-mypage`)
- [x] GitHub Actions CI/CD 파이프라인 (OIDC 기반 AWS 인증)
- [x] ECS 배포 자동화 (push to main → ECR push → ECS 재배포)

### Phase 3 — 대시보드 + 알림 ✅

- [x] AMG Workspace 생성 (SERVICE_MANAGED 인증)
- [x] AMP / CloudWatch / X-Ray 데이터소스 연결
- [x] Golden Signals 대시보드 (Latency, Traffic, Errors, Saturation)
- [x] AMP Recording Rules (RPS, 에러율, P99/P95/P50, Error Budget)

---

## 5. 배포 방법

### 초기 배포

```bash
cd terraform/environments/dev

# 환경변수 설정 (민감 정보)
export TF_VAR_database_url="postgresql+asyncpg://user:pass@host:5432/dbname"
export TF_VAR_jwt_secret_key="your-secret-key"
terraform init
terraform apply
```

### 앱 배포 (자동)

`codecaine-python-mypage` 레포 `main` 브랜치에 push하면 GitHub Actions가 자동으로 실행됩니다.

```
push to main
  → docker build & ECR push (sha-{commit} + latest 태그)
  → aws ecs update-service --force-new-deployment
  → aws ecs wait services-stable
```

### ADOT 설정 변경

```bash
# SSM 값 수정 후
aws ssm put-parameter \
  --name "/supplement-rec/dev/adot-config" \
  --value file://new-config.yaml \
  --overwrite

# ECS 재배포
aws ecs update-service \
  --cluster supplement-rec-dev \
  --service supplement-rec-dev \
  --force-new-deployment
```

---

## 6. 주요 리소스 정보 (dev)

| 리소스 | 값 |
|--------|-----|
| ALB URL | `http://supplement-rec-dev-alb-608069140.ap-northeast-2.elb.amazonaws.com` |
| AMP Workspace | `ws-afb01eed-4de6-4039-9591-b601028be501` |
| AMG (Grafana) URL | `https://g-30ff265d81.grafana-workspace.ap-northeast-2.amazonaws.com` |
| ECS Cluster | `supplement-rec-dev` |
| ECR Repository | `349132805116.dkr.ecr.ap-northeast-2.amazonaws.com/codecaine-python-mypage` |

---

## 7. 트러블슈팅 기록

### T1. `.terraform/` 디렉토리 git push 용량 초과
- **원인**: AWS Provider 바이너리(~686MB)가 포함되어 있었음
- **해결**: `.gitignore`에 `**/.terraform/`, `*.tfstate`, `*.tfstate.backup` 추가

### T2. Terraform Target Group 삭제 실패 (ResourceInUse)
- **원인**: 포트 변경(8080→8000)으로 Target Group 재생성 필요. Terraform이 Listener보다 먼저 TG를 삭제 시도
- **해결**: `name_prefix` + `lifecycle { create_before_destroy = true }` 적용

### T3. ECS Task 기동 실패 — ModuleNotFoundError
- **원인**: `opentelemetry-propagator-aws-xray` 패키지가 설치되어 있지만 직접 import 경로를 사용한 코드가 문제
- **해결**: 직접 import 제거. 패키지는 `OTEL_PROPAGATORS` 환경변수 entry point로만 사용

### T4. ECS Task 기동 실패 — Propagator xray not found
- **원인**: T3 해결 과정에서 패키지를 requirements.txt에서 제거했더니 `OTEL_PROPAGATORS=xray,tracecontext,baggage` 환경변수가 xray propagator를 못 찾음
- **해결**: `OTEL_PROPAGATORS`에서 `xray` 제거 → `tracecontext,baggage`로 변경

### T5. ECS Task 헬스체크 실패
- **원인**: `python:3.11-slim` 이미지에 `curl`이 없어 헬스체크 커맨드 실패
- **해결**: Dockerfile에 `RUN apt-get install -y curl` 추가

### T6. 계정 전환 후 ECS Task 실패 — 환경변수 누락
- **원인**: 새 계정 배포 시 `DATABASE_URL`, `JWT_SECRET_KEY` 환경변수가 Task Definition에 없었음
- **해결**: ECS 모듈에 `database_url`, `jwt_secret_key` 변수 추가, `TF_VAR_*` 환경변수로 주입

### T7. Grafana 대시보드 No Data
- **원인**: Recording Rules와 대시보드의 `job` 라벨이 `supplement-rec`으로 설정되어 있었으나, 실제 메트릭은 `supplement-rec-dev`로 전송됨
- **해결**: Recording Rules 및 대시보드 쿼리의 job 라벨을 `supplement-rec-dev`로 수정

---

## 8. 의미 있는 지표 설계

### Golden Signals

| 시그널 | 지표 |
|--------|------|
| Latency | P50/P95/P99 응답시간 (엔드포인트별) |
| Traffic | RPS, 동시 활성 요청 수 |
| Errors | 5xx 비율, 비즈니스 로직 에러 분류 |
| Saturation | CPU/메모리 사용률 vs 응답시간 |

### SLI/SLO

| SLI | 정의 | SLO |
|-----|------|-----|
| 가용성 | 성공 응답(2xx/3xx) / 전체 요청 | 99.9% (월간) |
| 레이턴시 | P99 < 200ms 비율 | 99% |

### AMP Recording Rules

| Rule | 설명 | 간격 |
|------|------|------|
| `job:http_requests_total:rate5m` | 엔드포인트별 RPS | 60s |
| `job:http_error_rate:rate5m` | 5xx 에러 비율 | 60s |
| `job:http_success_rate:rate5m` | 성공 요청 비율 (SLI) | 60s |
| `job:http_request_duration_ms:p99/p95/p50` | 레이턴시 백분위수 | 60s |
| `job:recommendation_api_duration_ms:p99` | 추천 API P99 | 60s |
| `job:error_budget_remaining:30d` | Error Budget 잔량 | 300s |

---

## 9. 예상 월 비용 (dev)

| 서비스 | 월 비용 |
|--------|--------|
| AMP | ~$4.56 |
| CloudWatch Logs | ~$4.05 |
| X-Ray | ~$1.00 |
| VPC Endpoints | ~$60.48 |
| ADOT Sidecar Fargate | ~$12.00 |
| AMG | ~$9.00 |
| **합계** | **~$91** |
