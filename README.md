# EKS 기반 Observability 스택 구축

AWS EKS 클러스터에 OpenTelemetry 기반 통합 관측가능성 스택을 구축하는 프로젝트입니다.  
로그 · 메트릭 · 트레이스 세 가지 신호를 단일 파이프라인으로 수집하고 Grafana에서 통합 조회합니다.

> **현재 상태**: 설계 완료 / 구현 진행 중

---

## 목표

- OpenTelemetry SDK로 애플리케이션 계측 (로그 · 메트릭 · 트레이스 동시 수집)
- ADOT Collector를 통한 신호별 백엔드 분기 전달
- Loki(로그) · Prometheus(메트릭) · Tempo(트레이스) 각 백엔드 구성
- Grafana 단일 인터페이스에서 세 신호 연계 조회
- 로그 → 트레이스 → 메트릭 상관관계 분석으로 장애 원인 추적 시간 단축

---

## 아키텍처

전체 데이터 흐름은 아래 문서에서 확인할 수 있습니다.

[OTEL 전체 데이터 흐름 시각화 보기](docs/otel-flow.html)

```
[ Application ]
      │  OTEL SDK 계측
      ▼
[ ADOT / OTEL Collector ]
      │  신호별 분기
      ├──► [ Loki ]       ← 로그
      ├──► [ Prometheus ] ← 메트릭
      └──► [ Tempo ]      ← 트레이스
                │
                ▼
          [ Grafana ]     ← 통합 시각화
```

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| Container Orchestration | AWS EKS |
| Instrumentation | OpenTelemetry SDK, ADOT Collector |
| 로그 | Loki |
| 메트릭 | Prometheus, Thanos |
| 트레이스 | Tempo |
| 시각화 | Grafana |
| 패키지 관리 | Helm |
| GitOps | ArgoCD |

---

## 구현 계획

### Phase 1 — 스택 설치
- [ ] EKS 클러스터 구성
- [ ] kube-prometheus-stack Helm 차트 설치 (Prometheus + Grafana + Alertmanager)
- [ ] Loki + Promtail 설치
- [ ] Tempo 설치
- [ ] ADOT Collector 설치 및 파이프라인 설정

### Phase 2 — 애플리케이션 계측
- [ ] OTEL SDK 연동 (로그 · 메트릭 · 트레이스)
- [ ] ADOT Collector → 백엔드 분기 확인
- [ ] Grafana 데이터소스 연결 (Loki, Prometheus, Tempo)

### Phase 3 — 대시보드 및 알림
- [ ] Golden Signals 대시보드 구성 (Latency, Traffic, Errors, Saturation)
- [ ] 로그 → 트레이스 연계 (Derived Fields 설정)
- [ ] Alertmanager 알림 규칙 설정

### Phase 4 — 장기 보관
- [ ] Thanos로 Prometheus 장기 메트릭 보관
- [ ] S3 백엔드 연동 (Loki Chunk, Tempo Block)

---

## 설계 문서

| 문서 | 설명 |
|------|------|
| [OTEL 전체 데이터 흐름](docs/otel-flow.html) | Application → SDK → Collector → Backend → Grafana 전체 흐름 |

---

## 기술 스택 요약

`AWS EKS` `OpenTelemetry` `ADOT Collector` `Prometheus` `Loki` `Tempo` `Thanos` `Grafana` `Helm` `ArgoCD`
