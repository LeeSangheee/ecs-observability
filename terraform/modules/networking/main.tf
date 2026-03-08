# =============================================================================
# networking 모듈 — VPC, 서브넷, 게이트웨이, VPC Endpoints
#
# 리소스 생성 순서:
#   1. VPC
#   2. 퍼블릭 서브넷 + 프라이빗 서브넷
#   3. Internet Gateway (퍼블릭 트래픽 진입점)
#   4. NAT Gateway (프라이빗 → 인터넷 아웃바운드 — ECS 이미지 Pull 등)
#   5. 라우팅 테이블 + 연결
#   6. VPC Endpoints (PrivateLink — NAT 비용 절감 + 보안)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # ECS Task가 AWS 서비스 DNS 이름을 해석할 수 있도록 활성화 필요
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

# -----------------------------------------------------------------------------
# 2-a. 퍼블릭 서브넷 (ALB, NAT Gateway 위치)
#
# map_public_ip_on_launch = true: 퍼블릭 서브넷에 배포된 리소스(ALB 등)가
# 자동으로 퍼블릭 IP를 할당받도록 합니다.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.public_subnet_azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-public-${count.index + 1}"
    # EKS/ALB Ingress Controller를 사용할 경우 이 태그가 필요합니다.
    # 현재 프로젝트는 ECS이므로 참고용입니다.
    "kubernetes.io/role/elb" = "1"
  })
}

# -----------------------------------------------------------------------------
# 2-b. 프라이빗 서브넷 (ECS Fargate Task 위치)
#
# ECS Task는 인터넷에 직접 노출되지 않습니다.
# 아웃바운드 트래픽은 NAT Gateway 또는 VPC Endpoint를 경유합니다.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.private_subnet_azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-private-${count.index + 1}"
  })
}

# -----------------------------------------------------------------------------
# 3. Internet Gateway (IGW)
#
# VPC와 인터넷 간 트래픽 허용. 퍼블릭 서브넷의 라우팅 테이블에 연결됩니다.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

# -----------------------------------------------------------------------------
# 4. Elastic IP + NAT Gateway
#
# NAT Gateway는 프라이빗 서브넷의 ECS Task가 인터넷으로 아웃바운드 통신할 때
# 사용합니다. (ECR 이미지 Pull, AWS API 호출 — VPC Endpoint 미설정 서비스 등)
#
# 비용 최적화 관점: VPC Endpoint가 설정된 서비스(xray, logs, monitoring, aps)는
# NAT Gateway를 경유하지 않으므로 NAT 데이터 처리 비용($0.059/GB)이 절감됩니다.
#
# 주의: NAT Gateway는 가용 영역 단위로 생성합니다. 단일 AZ 장애 시에도
# 다른 AZ의 ECS Task가 인터넷에 접근할 수 있도록 AZ별로 각각 생성합니다.
# 비용: NAT GW 시간당 $0.059 × 2 AZ ≈ 월 $87
# 비용 절감이 필요하면 NAT GW를 1개만 생성하되 단일 장애 지점(SPOF)이 생깁니다.
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  # IGW가 먼저 생성되어야 EIP가 VPC에 연결될 수 있습니다.
  depends_on = [aws_internet_gateway.main]

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-nat-eip-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "main" {
  count = length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-nat-gw-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# 5-a. 퍼블릭 라우팅 테이블
#
# 퍼블릭 서브넷의 모든 트래픽(0.0.0.0/0)을 IGW로 라우팅합니다.
# ALB가 인터넷에서 요청을 받을 수 있습니다.
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-public-rt"
  })
}

# 퍼블릭 서브넷과 퍼블릭 라우팅 테이블을 연결합니다.
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# 5-b. 프라이빗 라우팅 테이블 (AZ별 개별 생성)
#
# 각 AZ의 프라이빗 서브넷은 동일 AZ의 NAT Gateway로 트래픽을 라우팅합니다.
# AZ 간 NAT 트래픽을 최소화해 교차 AZ 데이터 전송 비용($0.01/GB)을 절감합니다.
# -----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-private-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# 6. VPC Endpoints (Interface 타입 — PrivateLink)
#
# ECS Task가 AWS 서비스와 통신할 때 인터넷 또는 NAT Gateway를 경유하지 않고
# AWS 내부 네트워크를 사용합니다.
#
# 효과:
#   - 보안: 트래픽이 인터넷에 노출되지 않음
#   - 비용: NAT Gateway 데이터 처리 비용 절감 (트래픽이 많을수록 유리)
#   - 성능: 낮은 레이턴시
#
# 주의: VPC Endpoint 자체 비용이 시간당 $0.014/AZ이므로
# 초기 소규모 트래픽에서는 NAT Gateway보다 비쌀 수 있습니다.
# =============================================================================

# VPC Endpoint용 보안 그룹
# 프라이빗 서브넷에서 HTTPS(443)로 접근하는 트래픽만 허용합니다.
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-${var.environment}-vpc-endpoints-sg"
  description = "VPC Interface Endpoints 보안 그룹 — 프라이빗 서브넷에서 HTTPS만 허용"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "VPC 내부에서 HTTPS 트래픽 허용 (ECS Task → VPC Endpoint)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # VPC Endpoint는 아웃바운드 트래픽을 허용할 필요가 없습니다.
  # (Endpoint가 AWS 서비스로 요청을 프록시하는 방향은 이 SG 아웃바운드와 무관)
  egress {
    description = "모든 아웃바운드 허용"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-vpc-endpoints-sg"
  })
}

# -----------------------------------------------------------------------------
# 6-a. X-Ray VPC Endpoint
#
# ADOT Sidecar가 X-Ray로 트레이스를 전송할 때 사용합니다.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "xray" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.xray"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  # DNS 이름으로 자동 라우팅 (별도 경로 설정 불필요)
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-endpoint-xray"
  })
}

# -----------------------------------------------------------------------------
# 6-b. CloudWatch Logs VPC Endpoint
#
# ADOT Sidecar가 로그를 CloudWatch Logs로 전송할 때 사용합니다.
# ECS awslogs 드라이버도 이 Endpoint를 통해 로그를 전송합니다.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-endpoint-logs"
  })
}

# -----------------------------------------------------------------------------
# 6-c. CloudWatch Monitoring VPC Endpoint
#
# CloudWatch Metrics API 호출 시 사용합니다.
# ECS Container Insights 메트릭 전송에도 활용됩니다.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "monitoring" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-endpoint-monitoring"
  })
}

# -----------------------------------------------------------------------------
# 6-d. AMP (Amazon Managed Prometheus) VPC Endpoint
#
# [주의] 서울 리전(ap-northeast-2)의 aps-workspaces VPC Endpoint 지원 여부가
# 불확실합니다. 지원 확인 전까지 create_amp_endpoint = false로 두세요.
# 미생성 시 ADOT의 AMP Remote Write 트래픽은 NAT Gateway를 경유합니다.
#
# 지원 확인 방법:
#   aws ec2 describe-vpc-endpoint-services \
#     --filters "Name=service-name,Values=com.amazonaws.ap-northeast-2.aps-workspaces" \
#     --region ap-northeast-2
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "amp" {
  count = var.create_amp_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.aps-workspaces"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-endpoint-amp"
  })
}

# -----------------------------------------------------------------------------
# 6-e. ECR VPC Endpoints (Gateway 방식 없음, Interface 필요)
#
# ECS Fargate에서 ECR 이미지를 Pull할 때 NAT Gateway를 경유하지 않도록 합니다.
# ecr.dkr: 이미지 레이어 Pull
# ecr.api: ECR API 호출 (이미지 메타데이터)
# s3(Gateway): ECR 이미지 레이어가 실제로는 S3에 저장됨
#
# 참고: ECS Fargate는 퍼블릭 ECR(public.ecr.aws)을 사용할 경우
# NAT Gateway를 통해 접근해야 합니다. ADOT 이미지(public.ecr.aws/...)가
# 이에 해당합니다.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-endpoint-ecr-dkr"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-endpoint-ecr-api"
  })
}

# S3 Gateway Endpoint (ECR 레이어 저장소)
# Gateway 타입은 별도 보안 그룹 불필요, 라우팅 테이블에 자동 추가됩니다.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  # 프라이빗 서브넷 라우팅 테이블에 S3 경로 자동 추가
  route_table_ids = aws_route_table.private[*].id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-endpoint-s3"
  })
}
