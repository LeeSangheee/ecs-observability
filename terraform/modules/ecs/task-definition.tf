# =============================================================================
# ECS Task Definition — App Container + ADOT Sidecar
#
# 컨테이너 구성:
#   [App Container]         [ADOT Sidecar]
#   포트 8080 리스닝    →   포트 4317 (gRPC) 리스닝
#   OTel SDK로 계측         메트릭/트레이스/로그 수집
#   OTLP 데이터 전송    →   AMP / X-Ray / CloudWatch로 내보내기
#
# 의존관계:
#   ADOT Sidecar는 App Container가 HEALTHY 상태가 된 이후에 시작됩니다.
#   (App이 먼저 OTLP 포트를 열어야 Sidecar가 연결을 수신할 수 있음)
#
# [주의] dependsOn은 Task Definition에서 컨테이너 시작 순서만 제어합니다.
# ADOT Sidecar가 장애가 나도 App Container의 헬스체크에는 영향이 없습니다.
# ADOT 장애 시 메트릭/트레이스 누락은 알람으로 감지하세요.
# =============================================================================

# CloudWatch Log Group 이름은 변수로 받습니다.
# Log Group 리소스는 observability 모듈(cloudwatch.tf)에서 생성합니다.
# Task Definition에서는 이름만 필요하므로 data 소스 대신 로컬 변수를 사용합니다.
# (data 소스 사용 시 observability 모듈보다 먼저 plan/apply되면 오류 발생)
locals {
  app_log_group_name  = "/ecs/${var.project}-${var.environment}"
  adot_log_group_name = "/ecs/${var.project}-${var.environment}/adot-collector"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # Fargate 필수. 컨테이너 간 localhost 통신 가능
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  # Task Execution Role: ECR Pull, CloudWatch 로그 그룹 생성 등 플랫폼 권한
  # 이 모듈의 iam.tf에서 생성한 Role을 직접 참조합니다.
  execution_role_arn = aws_iam_role.task_execution.arn

  # Task Role: 앱/ADOT가 AWS API(X-Ray, AMP, CloudWatch Logs)를 호출할 때 사용
  task_role_arn = var.adot_task_role_arn

  # 컨테이너 정의를 JSON으로 인라인 작성
  container_definitions = jsonencode([

    # =========================================================================
    # 1번 컨테이너: 영양제 추천 애플리케이션
    # =========================================================================
    {
      name  = "app"
      image = var.app_image

      # Fargate에서 Task CPU/Memory를 컨테이너 간에 분배
      # App: CPU 512 / Memory 1024
      cpu    = 512
      memory = 1024

      # 컨테이너가 사용하는 포트 (ALB Target Group이 이 포트로 트래픽 전달)
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port # awsvpc 모드에서는 containerPort와 동일
          protocol      = "tcp"
          name          = "http"
        }
      ]

      # 환경변수
      environment = [
        {
          # ADOT Sidecar는 같은 Task 내에서 localhost로 통신
          # awsvpc 네트워크 모드에서 컨테이너 간 localhost 공유
          name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
          value = "http://localhost:4317"
        },
        {
          name  = "OTEL_SERVICE_NAME"
          value = "${var.project}-${var.environment}"
        },
        {
          # 트레이스 전파 형식. AWS X-Ray와 호환되는 xray 형식 사용
          # W3C TraceContext도 함께 설정하면 외부 서비스와 트레이스 연계 가능
          name  = "OTEL_PROPAGATORS"
          value = "tracecontext,baggage"
        },
        {
          name  = "OTEL_RESOURCE_ATTRIBUTES"
          value = "deployment.environment=${var.environment}"
        }
      ]

      # 민감한 설정값은 환경변수가 아닌 Secrets Manager에서 주입합니다.
      # Phase 2에서 DB 비밀번호, API 키 등을 추가하세요.
      # secrets = [
      #   {
      #     name      = "DB_PASSWORD"
      #     valueFrom = "arn:aws:secretsmanager:...:secret:..."
      #   }
      # ]

      # 헬스체크
      # ADOT Sidecar가 이 헬스체크를 기준으로 의존성 판단
      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:${var.app_port}/health || exit 1"]
        interval    = 30  # 30초마다 체크
        timeout     = 5   # 5초 안에 응답 없으면 실패
        retries     = 3   # 3번 연속 실패 시 UNHEALTHY
        startPeriod = 60  # 컨테이너 시작 후 60초는 실패해도 카운트 안 함 (앱 초기화 시간)
      }

      # CloudWatch Logs 로그 드라이버
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project}-${var.environment}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
          # multiline-pattern: Java stacktrace 등 멀티라인 로그를 하나의 이벤트로 묶음
          # 필요 시 활성화하세요.
          # "awslogs-multiline-pattern" = "^(ERROR|WARN|INFO|DEBUG)"
        }
      }

      # 컨테이너가 종료 신호(SIGTERM)를 받은 후 강제 종료 전 대기 시간
      # ECS Service 업데이트 시 기존 Task가 진행 중인 요청을 완료할 수 있도록 합니다.
      stopTimeout = 30

      essential = true # 이 컨테이너가 종료되면 Task 전체 종료
    },

    # =========================================================================
    # 2번 컨테이너: ADOT Sidecar (AWS Distro for OpenTelemetry)
    #
    # 역할:
    #   - App에서 OTLP(gRPC 4317, HTTP 4318)로 받은 메트릭/트레이스/로그를
    #     각각 AMP / X-Ray / CloudWatch Logs로 내보냅니다.
    #   - ECS 컨테이너 메트릭(CPU, 메모리)을 awsecscontainermetrics 리시버로 수집합니다.
    #
    # 이미지 출처: https://gallery.ecr.aws/aws-observability/aws-otel-collector
    # 버전 고정 권장: latest 대신 v0.x.x 태그를 사용하면 갑작스러운 변경 방지
    # =========================================================================
    {
      name  = "adot-collector"
      image = "public.ecr.aws/aws-observability/aws-otel-collector:latest"

      # ADOT Sidecar: CPU 256 / Memory 512
      # memory_limiter processor에서 200MiB로 제한하므로 실제 사용량은 낮습니다.
      cpu    = 256
      memory = 512

      # ADOT 내부 포트 (로그/헬스체크용이며 외부에 노출하지 않음)
      portMappings = [
        {
          # OTLP gRPC 수신 포트 (App → ADOT)
          containerPort = 4317
          hostPort      = 4317
          protocol      = "tcp"
          name          = "otlp-grpc"
        },
        {
          # OTLP HTTP 수신 포트 (gRPC 불가능한 경우 폴백)
          containerPort = 4318
          hostPort      = 4318
          protocol      = "tcp"
          name          = "otlp-http"
        },
        {
          # ADOT 내부 확장 포트 (pprof, zpages 등 디버깅용)
          containerPort = 13133
          hostPort      = 13133
          protocol      = "tcp"
          name          = "health"
        }
      ]

      # SSM Parameter Store에서 ADOT 설정을 읽어 AOT_CONFIG_CONTENT 환경변수로 주입합니다.
      # 설정 변경 시 이미지 재빌드 없이 SSM 값만 수정 후 ECS Service 재배포하면 됩니다.
      command = ["--config=env:AOT_CONFIG_CONTENT"]

      environment = [
        {
          # AWS 리전 명시 (ADOT SDK가 SigV4 서명 시 사용)
          name  = "AWS_REGION"
          value = var.region
        }
      ]

      # SSM Parameter Store에서 ADOT 설정 YAML을 AOT_CONFIG_CONTENT로 주입
      # Task Execution Role에 ssm:GetParameters 권한이 있어야 합니다. (iam.tf에서 부여됨)
      secrets = [
        {
          name      = "AOT_CONFIG_CONTENT"
          valueFrom = var.adot_config_ssm_arn
        }
      ]

      # 헬스체크: ADOT 내장 health 확장 포트 사용
      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:13133/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      # App Container가 HEALTHY가 된 이후에 ADOT 시작
      # 이 설정이 없으면 ADOT이 먼저 시작되고 App이 아직 OTLP 데이터를 보내지 않아
      # "connection refused" 오류가 로그에 남을 수 있습니다. (기능상 문제는 없음)
      dependsOn = [
        {
          containerName = "app"
          condition     = "HEALTHY"
        }
      ]

      # CloudWatch Logs 로그 드라이버
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project}-${var.environment}/adot-collector"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "adot"
        }
      }

      stopTimeout = 30

      # ADOT Sidecar가 종료되어도 App Container는 계속 실행됩니다.
      # 단, 메트릭/트레이스 전송이 중단됩니다.
      # 알람으로 ADOT 장애를 감지하세요 (observability/alarms.tf 참조).
      essential = false
    }
  ])

  tags = var.tags
}
