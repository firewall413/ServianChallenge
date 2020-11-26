terraform {
  backend "s3" {
    bucket  = "servian-challenge-terraformstate"
    key     = "service/terraform.tfstate"
    encrypt = true
    region  = "ap-southeast-2"
  }
}