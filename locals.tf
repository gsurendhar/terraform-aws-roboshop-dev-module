locals {
  vpc_id = data.aws_ssm_parameter.vpc_id.value
  ami_id             = data.aws_ami.devops.id
  private_subnet_id = split(",", data.aws_ssm_parameter.private_subnet_ids.value)[0]
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  sg_id    = data.aws_ssm_parameter.sg_id.value
  backend_alb_listener_arn = data.aws_ssm_parameter.backend_alb_listener_arn.value
  frontend_alb_listener_arn = data.aws_ssm_parameter.frontend_alb_listener_arn.value

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Terraform   = true
  }

  Name = "${var.project}-${var.environment}"


  tg_port            = var.component == "frontend" ? 80 : 8080
  health_check_path  = var.component == "frontend" ? "/" : "/health"
  alb_listener_arn   = var.component == "frontend" ? local.frontend_alb_listener_arn : local.backend_alb_listener_arn
  rule_host_header   = var.component == "frontend" ? "${var.environment}.gonela.site" : "${var.component}.backend-${var.environment}.gonela.site"
}