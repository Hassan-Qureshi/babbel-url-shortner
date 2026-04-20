terraform {
  backend "s3" {
    bucket         = "babbel-url-shortener-terraform-state"
    key            = "vpc/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "url-shortener-terraform-locks"
    encrypt        = true
  }
}

