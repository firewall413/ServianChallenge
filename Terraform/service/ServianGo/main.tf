terraform {
 backend "s3" {
   bucket         = "myorg-terraform-environmentname"
   key            = "service/terraform.tfstate"
   region         = "us-east-1"
   encrypt        = true
   dynamodb_table = "terraform-lock"
 }
}

data "aws_subnet_ids" "app_subnet_ids" {
  vpc_id = "${var.app-vpc-id}"

  tags {
    SubnetType = "private"
  }
}


data "aws_security_groups" "vbb" {
  filter {
    name   = "group-name"
    values = ["${var.virtualbiobank-sg-name}"]
  }
}


# -------------------------------------------------------------
# ALB
# -------------------------------------------------------------

resource "aws_lb" "alb" {
  name               = "ServianGo-alb"
  load_balancer_type = "application"

  subnets         = ["${data.aws_subnet_ids.alb_subnet_ids.ids}"]
  security_groups = ["${aws_security_group.lb_sg.id}"]
  internal        = "false"
  idle_timeout    = "600"

  enable_deletion_protection = true

  tags = "${var.tags}"

  access_logs {
    bucket  = "${data.aws_s3_bucket.logging_bucket.id}"
    prefix  = "${data.aws_s3_bucket.logging_bucket.id}-elb"
    enabled = true
  }
}

resource "aws_lb_listener" "listener_https" {
  load_balancer_arn = "${aws_lb.alb.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn   = "${data.aws_acm_certificate.cert.arn}"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group_443.arn}"
  }
}

resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = "${aws_lb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_302"
    }
  }
}

resource "aws_lb_target_group" "target_group_443" {
  name                 = "${var.project}-${var.account}-${var.app-name}-${var.environment}-443"
  port                 = 443
  protocol             = "HTTPS"
  vpc_id               = "${var.app-vpc-id}"
  deregistration_delay = 120

  stickiness = {
    type            = "lb_cookie"
    cookie_duration = 86400       # 1 day
    enabled         = true
  }

  health_check {
    protocol            = "HTTPS"
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = "${aws_autoscaling_group.asg.id}"
  alb_target_group_arn   = "${aws_lb_target_group.target_group_443.arn}"
  depends_on             = ["aws_autoscaling_group.asg", "aws_lb_target_group.target_group_443"]
}

# -------------------------------------------------------------
# Autoscaling Groups
# -------------------------------------------------------------

resource "aws_launch_template" "lt" {
  name                                 = "${var.project}-${var.account}-${var.app-name}-${var.environment}-lt"
  image_id                             = "${data.aws_ami.ami.image_id}"
  instance_type                        = "${var.scaling-instance-type}"
  key_name                             = "${var.key-name}"
  disable_api_termination              = false
  instance_initiated_shutdown_behavior = "stop"

  /*
    REPLACE ME WITH USERDATA IF REQUIRED
    user_data                            = "${base64encode(data.template_file.userdata.rendered)}"
  */

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = "gp2"
      volume_size           = 120
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = "${data.aws_kms_key.ebs.arn}"
    }
  }
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = false
    security_groups             = ["${aws_security_group.ec2_sg.id}"]
    delete_on_termination       = true
    description                 = "${var.project}-${var.account}-${var.app-name}-${var.environment}"
  }
  iam_instance_profile {
    name = "${aws_iam_instance_profile.ec2_profile.name}"
  }
  capacity_reservation_specification {
    capacity_reservation_preference = "none"
  }
  credit_specification {
    cpu_credits = "standard"
  }
  monitoring {
    enabled = true
  }
  tag_specifications {
    resource_type = "volume"
    tags          = "${local.common_tags}"
  }
  tag_specifications {
    resource_type = "instance"
    tags          = "${local.common_tags}"
  }
}

resource "aws_autoscaling_group" "asg" {
  launch_template {
    id      = "${aws_launch_template.lt.id}"
    version = "$Latest"
  }

  vpc_zone_identifier = ["${data.aws_subnet_ids.app_subnet_ids.ids}"]
  name                = "${var.project}-${var.account}-${var.app-name}-${var.environment}-asg"

  min_size         = "${var.scaling-min-size}"
  max_size         = "${var.scaling-max-size}"
  min_elb_capacity = "${var.scaling-min-elb-capacity}" # optional - Setting this causes Terraform to wait for this number of instances to show up healthy in the ELB only on creation
  desired_capacity = "${var.scaling-desired-capacity}"

  wait_for_capacity_timeout = "20m"
  health_check_grace_period = 1200
  health_check_type         = "ELB"
  force_delete              = true
  default_cooldown          = 300

  suspended_processes = [
    "Terminate",
  ]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  depends_on = [
    "aws_launch_template.lt",
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = "${local.asg_tags}"
}

resource "aws_autoscaling_policy" "asg_scaling_policy_up" {
  name                   = "${local.name-prefix}-asg-policy-up"
  autoscaling_group_name = "${aws_autoscaling_group.asg.name}"
  policy_type            = "SimpleScaling"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 600
  depends_on             = ["aws_autoscaling_group.asg"]
}

resource "aws_autoscaling_policy" "asg_scaling_policy_down" {
  name                   = "${local.name-prefix}-asg-policy-down"
  autoscaling_group_name = "${aws_autoscaling_group.asg.name}"
  policy_type            = "SimpleScaling"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 600
  depends_on             = ["aws_autoscaling_group.asg"]
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high_alarm" {
  alarm_name          = "${local.name-prefix}-asg-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "10"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "60"
  alarm_description   = "${local.name-prefix} >= 60 CPU utilisation"

  alarm_actions = [
    "${aws_autoscaling_policy.asg_scaling_policy_up.arn}",
  ]

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.asg.name}"
  }

  depends_on = ["aws_autoscaling_policy.asg_scaling_policy_up"]
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_low_alarm" {
  alarm_name          = "${local.name-prefix}-asg-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "10"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "60"
  alarm_description   = "${local.name-prefix} <= 60 CPU utilisation"

  alarm_actions = [
    "${aws_autoscaling_policy.asg_scaling_policy_down.arn}",
  ]

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.asg.name}"
  }

  depends_on = ["aws_autoscaling_policy.asg_scaling_policy_down"]
}

module "efs_mytardis" {
  source = "../../modules/module-efs"

  # Environment
  app-name           = "${var.app-name}"
  customer           = "${var.customer}"
  child-account-id   = "${data.aws_caller_identity.current.account_id}"
  child-account-name = "${var.account}"
  child-project      = "${var.project}"
  child-account-env  = "${var.environment}"

  # Placement
  vpc-id     = "${var.app-vpc-id}"
  subnet-ids = ["${data.aws_subnet_ids.app_subnet_ids.ids}"]
  throughput = "20"

  # Security
  allow-based-on-cidr     = false
  allow-based-on-sg       = true
  allowed-cidr-blocks     = ["${data.aws_vpc.selected.cidr_block}"]                                   # Dummy value as we're not allowing a CIDR
  allowed-security-groups = ["${aws_security_group.ec2_sg.id}","${data.aws_security_groups.vbb.ids}"]
}
