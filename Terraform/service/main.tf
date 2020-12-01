# -------------------------------------------------------------
# Terraform config in S3
# -------------------------------------------------------------
provider "aws" {
  region = "ap-southeast-2"
  version = "~> 3.0"
}
terraform {
  backend "s3" {
    bucket  = "servian-challenge-terraformstate"
    key     = "service/terraform.tfstate"
    encrypt = true
    region  = "ap-southeast-2"
  }
}

data "terraform_remote_state" "shared" {
 backend = "s3" 
 config = {
   bucket = "servian-challenge-terraformstate"
   key    = "shared/serviangolangapp.tfstate"
   region = "ap-southeast-2"
 }
}

# -------------------------------------------------------------
# Get Postgress DB User & PW
# -------------------------------------------------------------
data "aws_ssm_parameter" "servianchallenge_postgresdb_user" {
  name = "servianchallenge_postgresdb_user"
}
data "aws_ssm_parameter" "servianchallenge_postgresdb_pw" {
  name = "servianchallenge_postgresdb_pw"
}
# -------------------------------------------------------------
# RDS instance
# -------------------------------------------------------------
resource "aws_db_instance" "db_instance" {
 engine                  = "postgres"
 allocated_storage       = "8"
 instance_class          = "db.t2.micro"
 name                    = "servianappdb"
 identifier              = "servianappdb"
 username                = data.aws_ssm_parameter.servianchallenge_postgresdb_user.value
 password                = data.aws_ssm_parameter.servianchallenge_postgresdb_pw.value
 multi_az                  = true
 db_subnet_group_name    = data.terraform_remote_state.shared.outputs.db_subnet_group_name
 vpc_security_group_ids  = [data.terraform_remote_state.shared.outputs.vpc_default_sg_id]
 skip_final_snapshot     = true // <- not recommended for production
}
# -------------------------------------------------------------
# Security Group
# -------------------------------------------------------------
resource "aws_security_group" "public_http" {
 name        = "public-http"
 description = "Allow HTTP traffic from public"
 vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id
}
resource "aws_security_group_rule" "public_http" {
 type              = "ingress"
 from_port         = 80
 to_port           = 80
 protocol          = "tcp"
 security_group_id = aws_security_group.public_http.id
 cidr_blocks       = ["0.0.0.0/0"]
}
# -------------------------------------------------------------
# Load Balancing
# -------------------------------------------------------------
#  Create ALB
resource "aws_alb" "alb" {
 name            = "alb-myapp"
 internal        = false
 security_groups = [data.terraform_remote_state.shared.outputs.vpc_default_sg_id, aws_security_group.public_http.id]
 subnets         = data.terraform_remote_state.shared.outputs.public_subnet_ids
}

#  Create target group for ALB
resource "aws_alb_target_group" "default" {
 name     = "tg-myapp"
 port     = "80"
 protocol = "HTTP"
 vpc_id   = data.terraform_remote_state.shared.outputs.vpc_id
 stickiness {
   type = "lb_cookie"
 }
}

#  Create listeners to connect ALB to target group
resource "aws_alb_listener" "http" {
 load_balancer_arn = aws_alb.alb.arn
 port              = "80"
 protocol          = "HTTP"
#  ssl_policy        = "ELBSecurityPolicy-2016-08"
#  certificate_arn   = "${data.aws_acm_certificate.sslcert.arn}"
 default_action {
   target_group_arn = aws_alb_target_group.default.arn
   type             = "forward"
 }
}

# -------------------------------------------------------------
# ECS Task Definition
# -------------------------------------------------------------
data "template_file" "task_def" {
 template = file("${path.module}/task-definition.json")
 vars = {
   dbhost = aws_db_instance.db_instance.address
   dbuser = data.aws_ssm_parameter.servianchallenge_postgresdb_user.value
   dbpw = data.aws_ssm_parameter.servianchallenge_postgresdb_pw.value
   hostname   = "http://${aws_alb.alb.dns_name}/"
 }
}

# Create task definition
resource "aws_ecs_task_definition" "td" {
 family                = "myapp"
 container_definitions = data.template_file.task_def.rendered
 network_mode          = "bridge"
}

# Create ECS Service
resource "aws_ecs_service" "service" {
 name                               = "myapp"
 cluster                            = data.terraform_remote_state.shared.outputs.ecs_cluster_name
 desired_count                      = length(data.terraform_remote_state.shared.outputs.aws_zones)
 iam_role                           = data.terraform_remote_state.shared.outputs.ecsServiceRole_arn
 deployment_maximum_percent         = "200"
 deployment_minimum_healthy_percent = "50"
 ordered_placement_strategy {
   type  = "spread"
   field = "instanceId"
 }
 load_balancer {
   target_group_arn = aws_alb_target_group.default.arn
   container_name   = "web"
   container_port   = "3000"
 }
 task_definition = "${aws_ecs_task_definition.td.family}:${aws_ecs_task_definition.td.revision}"
}


# # -------------------------------------------------------------
# # Create DNS Record
# # -------------------------------------------------------------
# resource "route53_record" "pmadns" {
#  domain  = "${var.cloudflare_domain}"
#  name    = "pma"
#  value   = "${aws_alb.alb.dns_name}"
#  type    = "CNAME"
#  proxied = true
# }