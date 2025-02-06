terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  shared_config_files      = ["/Users/evanwu/.aws/config"]
  shared_credentials_files = ["/Users/evanwu/.aws/credentials"]
  profile                  = "e8wu"
}
