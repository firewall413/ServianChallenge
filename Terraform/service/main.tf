# -------------------------------------------------------------
# Terraform config in S3
# -------------------------------------------------------------
provider "aws" {
  region = "ap-southeast-2"
  version = "~> 3.0"
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
# RDS instance
# -------------------------------------------------------------
resource "aws_db_instance" "db_instance" {
 engine                  = "PostgreSQL"
 allocated_storage       = "8"
 instance_class          = "db.t2.micro"
 name                    = "mydatabase"
 identifier              = "mydatabase"
 username                = "dbuser"
 password                = "dbpass1234"
 multi_az                  = true
 db_subnet_group_name    = data.terraform_remote_state.shared.outputs.db_subnet_group_name
 vpc_security_group_ids  = [data.terraform_remote_state.shared.outputs.vpc_default_sg_id]
 skip_final_snapshot     = true // <- not recommended for production
}
# -------------------------------------------------------------
# Security Group
# -------------------------------------------------------------
resource "aws_security_group" "public_https" {
 name        = "public-https"
 description = "Allow HTTPS traffic from public"
 vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id
}
resource "aws_security_group_rule" "public_https" {
 type              = "ingress"
 from_port         = 443
 to_port           = 443
 protocol          = "tcp"
 security_group_id = aws_security_group.public_https.id
 cidr_blocks       = ["0.0.0.0/0"]
}
# -------------------------------------------------------------
# ALB
# -------------------------------------------------------------
resource "aws_alb" "alb" {
 name            = "alb-myapp"
 internal        = false
 security_groups = [data.terraform_remote_state.shared.outputs.vpc_default_sg_id, aws_security_group.public_https.id]
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

resource "aws_alb_listener" "https" {
 load_balancer_arn = aws_alb.alb.arn
 port              = "443"
 protocol          = "HTTPS"
 ssl_policy        = "ELBSecurityPolicy-2016-08"
#  certificate_arn   = "${data.aws_acm_certificate.sslcert.arn}"
 default_action {
   target_group_arn = aws_alb_target_group.default.arn
   type             = "forward"
 }
}