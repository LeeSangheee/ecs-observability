# ECS Fargate 기반 Observability 스택 구축

AWS ECS Fargate 환경에 OpenTelemetry 기반 통합 관측가능성 스택을 구축하는 프로젝트입니다.  
로그 · 메트릭 · 트레이스 세 가지 신호를 단일 파이프라인으로 수집하고 Grafana에서 통합 조회합니다.

> **현재 상태**: 설계 완료 / 구현 진행 중

---

## 목표

- OTEL SDK로 애플리케이션 계측 (로그 · 메트릭 · 트레이스 동시 수집)
- ADOT Collector를 ECS 태스크 내 사이드카 컨테이너로 배치하여 신호별 백엔드 분기 전달
- Loki(로그) · Prometheus(메트릭) · Tempo(트레이스) 각 백엔드 구성
- Grafana 단일 인터페이스에서 세 신호 연계 조회
- 로그 → 트레이스 → 메트릭 상관관계 분석으로 장애 원인 추적 시간 단축

---

## 아키텍처

전체 데이터 흐름은 아래 문서에서 확인할 수 있습니다.

[OTEL 전체 데이터 흐름 시각화 보기](https://leesangheee.github.io/ecs-observability/docs/otel-flow.html)

```
[ ECS Task (Fargate) ]
┌─────────────────────────────────┐
│  [ App Container ]              │
│       │  OTEL SDK 계측          │
│       ▼                         │
│  [ ADOT Sidecar Container ]     │
│       │  OTLP gRPC (4317)       │
└───────┼─────────────────────────┘
        │  신호별 분기
        ├──► [ Loki ]        ← 로그
        ├──► [ Prometheus ]  ← 메트릭
        └──► [ Tempo ]       ← 트레이스
                  │
                  ▼
            [ Grafana ]      ← 통합 시각화
```

**ADOT Sidecar 방식을 선택한 이유**

Fargate는 노드 레벨 DaemonSet을 사용할 수 없어 Collector를 별도 인프라로 띄우거나  
태스크 내 사이드카로 배치해야 합니다. 사이드카 방식은 앱 컨테이너와 생명주기를 함께하여  
네트워크 오버헤드 없이 localhost로 통신할 수 있고, 태스크 단위로 Collector 설정을  
독립적으로 관리할 수 있는 장점이 있습니다.

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| Container Orchestration | AWS ECS Fargate |
| Instrumentation | OpenTelemetry SDK, ADOT Collector (sidecar) |
| 로그 | Loki |
| 메트릭 | Prometheus, Thanos |
| 트레이스 | Tempo |
| 시각화 | Grafana |
| IaC | Terraform |
| CI/CD | GitHub Actions |

---

## 구현 계획

### Phase 1 — 인프라 구성
- [ ] ECS Fargate 클러스터 및 태스크 정의 구성
- [ ] ADOT Collector 사이드카 컨테이너 태스크 정의에 추가
- [ ] Prometheus, Loki, Tempo 백엔드 구성
- [ ] Grafana 설치 및 데이터소스 연결

### Phase 2 — 애플리케이션 계측
- [ ] OTEL SDK 연동 (로그 · 메트릭 · 트레이스)
- [ ] ADOT Collector 파이프라인 설정 (receiver → processor → exporter)
- [ ] 백엔드별 데이터 수집 확인

### Phase 3 — 대시보드 및 알림
- [ ] Golden Signals 대시보드 구성 (Latency, Traffic, Errors, Saturation)
- [ ] 로그 → 트레이스 연계 (Grafana Derived Fields 설정)
- [ ] Alertmanager 알림 규칙 설정

### Phase 4 — 장기 보관
- [ ] Thanos로 Prometheus 장기 메트릭 보관
- [ ] S3 백엔드 연동 (Loki Chunk, Tempo Block)

---

## 설계 문서

| 문서 | 설명 |
|------|------|
| [OTEL 전체 데이터 흐름](https://leesangheee.github.io/ecs-observability/docs/otel-flow.html) | App → ADOT Sidecar → Backend → Grafana 전체 흐름 시각화 |

---

## 기술 스택 요약

`AWS ECS Fargate` `OpenTelemetry` `ADOT Collector` `Prometheus` `Loki` `Tempo` `Thanos` `Grafana` `Terraform` `GitHub Actions`
