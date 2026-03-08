# =============================================================================
# ecs 모듈 — ECS Cluster, ALB, Security Groups, ECS Service
#
# 리소스 생성 순서:
#   1. Security Groups (ALB용, ECS Task용)
#   2. ALB (Application Load Balancer) + Target Group + Listener
#   3. ECS Cluster
#   4. ECS Service
# =============================================================================

# =============================================================================
# 1. Security Groups
# =============================================================================

# ALB 보안 그룹 — 인터넷에서 HTTP/HTTPS 트래픽을 수신합니다.
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "ALB 보안 그룹 — 인터넷에서 HTTP(80) 및 HTTPS(443) 수신"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP 트래픽 수신 (HTTPS 리다이렉트 목적)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS 트래픽 수신"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "ECS Task로의 아웃바운드 트래픽 허용"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb-sg"
  })
}

# ECS Task 보안 그룹 — ALB에서 오는 트래픽만 수신합니다.
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project}-${var.environment}-ecs-tasks-sg"
  description = "ECS Task 보안 그룹 — ALB에서 오는 트래픽만 허용"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ALB에서 App 포트로 트래픽 허용"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # ECS Task → AWS 서비스 아웃바운드 (VPC Endpoint 또는 NAT GW 경유)
  egress {
    description = "모든 아웃바운드 허용 (ECR Pull, AWS API 호출 등)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ecs-tasks-sg"
  })
}

# =============================================================================
# 2. Application Load Balancer (ALB)
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false # 인터넷에서 접근 가능한 외부 ALB
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # 삭제 보호: prod 환경에서는 true로 설정하세요.
  enable_deletion_protection = false

  # ALB 액세스 로그 (S3 버킷 필요 — Phase 2에서 활성화 예정)
  # access_logs {
  #   bucket  = "your-alb-access-logs-bucket"
  #   prefix  = "${var.project}-${var.environment}"
  #   enabled = true
  # }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb"
  })
}

# Target Group — ALB가 ECS Task의 app 포트로 트래픽을 전달합니다.
resource "aws_lb_target_group" "app" {
  name        = "${var.project}-${var.environment}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate는 ip 타입 필수 (awsvpc 네트워크 모드)

  health_check {
    enabled             = true
    healthy_threshold   = 2   # 2번 성공하면 Healthy
    unhealthy_threshold = 3   # 3번 실패하면 Unhealthy
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200" # 200 OK만 정상으로 판단
  }

  # Connection Draining: Target이 등록 해제될 때 기존 연결이 완료될 때까지 대기
  deregistration_delay = 30

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-tg"
  })
}

# ALB HTTP Listener (포트 80)
# 운영 환경에서는 HTTPS로 리다이렉트 처리합니다.
# 현재는 개발 편의를 위해 직접 전달합니다.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn

    # [운영 환경 권장] HTTP → HTTPS 리다이렉트
    # default_action {
    #   type = "redirect"
    #   redirect {
    #     port        = "443"
    #     protocol    = "HTTPS"
    #     status_code = "HTTP_301"
    #   }
    # }
  }

  tags = var.tags
}

# =============================================================================
# 3. ECS Cluster
#
# Container Insights: 활성화하면 ECS Task의 CPU, 메모리 등을 CloudWatch에
# 자동으로 수집합니다. 비용이 추가되지만 초기 관측가능성 확보에 유용합니다.
# =============================================================================
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-cluster"
  })
}

# Cluster Capacity Providers 설정
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  # Fargate: 온디맨드
  # Fargate Spot: 최대 70% 비용 절감 (단, 중단될 수 있음 — 개발 환경에 적합)
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1 # 최소 1개의 Task는 반드시 FARGATE로 실행
  }
}

# =============================================================================
# 4. ECS Service
#
# ECS Service는 원하는 수의 Task를 항상 실행 상태로 유지합니다.
# Task가 실패하면 자동으로 새 Task를 시작합니다.
# =============================================================================
resource "aws_ecs_service" "app" {
  name            = "${var.project}-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # 새 Task가 정상적으로 시작될 때까지 최소 실행할 Task 비율
  # 100: 배포 중에도 원하는 Task 수를 항상 유지 (롤링 배포)
  deployment_minimum_healthy_percent = 100
  # 배포 중 최대 Task 수 비율 (200: 새 Task + 기존 Task 동시에 2배까지)
  deployment_maximum_percent         = 200

  # Circuit Breaker: 배포 실패 시 자동 롤백
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # awsvpc 네트워크 모드 설정
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # 프라이빗 서브넷 → 퍼블릭 IP 불필요
  }

  # ALB Target Group에 ECS Service 연결
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  # Service Discovery (Cloud Map) — 서비스 간 직접 통신이 필요한 경우 활성화
  # service_registries { ... }

  # Task Definition 변경 시 Service 자동 업데이트를 위해
  # 아래 lifecycle 설정을 추가합니다.
  lifecycle {
    ignore_changes = [
      # 외부(Auto Scaling)에서 desired_count를 변경해도 Terraform이 되돌리지 않음
      desired_count
    ]
  }

  tags = var.tags
}

# =============================================================================
# Auto Scaling
#
# ECS Service의 Task 수를 CPU/메모리 사용률에 따라 자동으로 조정합니다.
# =============================================================================
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU 사용률 기반 스케일링
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project}-${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70.0 # CPU 70% 목표

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_in_cooldown  = 300 # 스케일 인 후 300초 대기
    scale_out_cooldown = 60  # 스케일 아웃 후 60초 대기 (빠른 확장 우선)
  }
}

# 메모리 사용률 기반 스케일링
resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.project}-${var.environment}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 75.0 # 메모리 75% 목표

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
