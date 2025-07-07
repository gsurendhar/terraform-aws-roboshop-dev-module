# Backend_ALB Target_group of component
resource "aws_lb_target_group" "main" {
  name     = "${local.Name}-${var.component}"
  port     = local.tg_port
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  health_check {
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200-299"
    path                = local.health_check_path
    port                = local.tg_port
    timeout             = 2
    unhealthy_threshold = 3
  }
}

#  instance creation
resource "aws_instance" "main" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  subnet_id              = local.private_subnet_id
  tags = merge(
    local.common_tags,
    {
      Name = "${local.Name}-${var.component}"
    }
  )
}

# component configuration using ansible-pull 
resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]

  provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }
  connection {
    type     = "ssh"
    user     = "ec2-user"
    password = "DevOps321"
    host     = aws_instance.main.private_ip
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo bash /tmp/bootstrap.sh ${var.component}"
    ]
  }
}

# Stop the instance for taking ami after provisioning
resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on  = [terraform_data.main]
}

# taking AMI of Stopped component instance
resource "aws_ami_from_instance" "main" {
  name               = "${local.Name}-${var.component}"
  source_instance_id = aws_instance.main.id
  depends_on         = [aws_ec2_instance_state.main]
}

# terminating the component instance after taking AMI
resource "terraform_data" "main_delete" {
  triggers_replace = [
    aws_instance.main.id
  ]
  # to execute aws command you must have aws configure in your laptop
  provisioner "local-exec" {
   command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id} "
  }
  depends_on = [aws_ami_from_instance.main]
}


# creating component launch template for ASG
resource "aws_launch_template" "main" {
  name = "${local.Name}-${var.component}"
  image_id = aws_ami_from_instance.main.id
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  update_default_version = true

  # instance tags
  tag_specifications {
    resource_type = "instance"

    tags = merge (
      local.common_tags,
      {
      Name = "${local.Name}-${var.component}"
      }
    )
  }

  # volume tags
  tag_specifications {
    resource_type = "volume"

    tags = merge (
      local.common_tags,
      {
      Name = "${local.Name}-${var.component}"
      }
    )
  }

  # launch template tags
  tags = merge (
    local.common_tags,
    {
    Name = "${local.Name}-${var.component}"
    }
  )
}

# component ASG
resource "aws_autoscaling_group" "main" {
  name                      = "${local.Name}-${var.component}"
  desired_capacity          = 1
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 90
  health_check_type         = "ELB"
  vpc_zone_identifier       = local.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.main.arn] 
 
 
  launch_template {
    id      = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }
  

  dynamic "tag" {
    for_each = merge(
      local.common_tags,
      {
        Name  = "${local.Name}-${var.component}"
      }
    )

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  timeouts {
    delete = "15m"
  }

}

# ASG Policy
resource "aws_autoscaling_policy" "main" {
  name                   = "${local.Name}-${var.component}"
  autoscaling_group_name = aws_autoscaling_group.main.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }
}

# ALB Listener Rule
resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn
  priority     = var.rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [local.rule_host_header]
    }
  }
}