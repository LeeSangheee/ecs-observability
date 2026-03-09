# =============================================================================
# SSM Parameter Store — ADOT Collector Config
#
# ADOT 설정 파일을 SSM에 저장하고 ECS Task Definition secrets로 주입합니다.
# Task Execution Role이 이 파라미터를 읽어 AOT_CONFIG_CONTENT 환경변수로 주입합니다.
#
# 이미지 재빌드 없이 ADOT 설정을 변경할 수 있습니다.
# 변경 후 ECS Service를 업데이트(재배포)해야 새 설정이 적용됩니다.
# =============================================================================

resource "aws_ssm_parameter" "adot_config" {
  name        = "/${var.project}/${var.environment}/adot-config"
  description = "ADOT collector configuration for ${var.project}-${var.environment}"
  type        = "String"

  value = templatefile("${path.module}/templates/adot-collector-config.yaml.tpl", {
    region = var.region

    # AMP Remote Write endpoint: prometheus_endpoint 끝에 api/v1/remote_write 추가
    amp_remote_write_endpoint = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"

    service_name    = "${var.project}-${var.environment}"
    environment     = var.environment
    app_log_group   = "/ecs/${var.project}-${var.environment}"
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-adot-config"
  })
}
