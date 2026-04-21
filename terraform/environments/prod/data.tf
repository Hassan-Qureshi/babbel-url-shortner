data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "babbel-url-shortener-terraform-state"
    key    = "vpc/terraform.tfstate"
    region = "eu-central-1"
  }
}
locals {
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
}
