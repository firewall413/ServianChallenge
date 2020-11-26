variable "public_key_path" {
  description = "Path to the SSH public key to be used for authentication."
  default = "/c:/Users/Administrator/.ssh/ddpm_keypair_arno.pub"
}

variable "private_key_path" {
  description = "Path to the SSH private key to be used for authentication."
  default = "/c:/Users/Administrator/.ssh/ddpm_keypair_arno.pem"
}

variable "key_name" {
  description = "Desired name of AWS key pair."
  default = "ddpm_keypair_arno"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "ap-southeast-2"
}

variable "aws_profile" {
  description = "AWS profile used"
  default     = "arnoroos"
}

variable "aws_zones" {
 type        = list
 description = "List of availability zones to use"
 default     = ["ap-southeast-2a","ap-southeast-2b","ap-southeast-2c"]
}