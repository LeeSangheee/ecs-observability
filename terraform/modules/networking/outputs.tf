# =============================================================================
# networking 모듈 — 출력값 정의
#
# 다른 모듈(ecs, observability)에서 참조할 네트워킹 리소스 ID를 노출합니다.
# =============================================================================

output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR 블록"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록 (ALB 배포용)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (ECS Task 배포용)"
  value       = aws_subnet.private[*].id
}

output "vpc_endpoint_sg_id" {
  description = "VPC Endpoint 보안 그룹 ID"
  value       = aws_security_group.vpc_endpoints.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway ID 목록"
  value       = aws_nat_gateway.main[*].id
}

output "nat_public_ips" {
  description = "NAT Gateway 퍼블릭 IP 목록 (외부 서비스 허용 목록 등록용)"
  value       = aws_eip.nat[*].public_ip
}
