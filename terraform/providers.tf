provider "aws" {
  region = "us-west-2"

  shared_config_files      = ["/Users/evanwu/.aws/config"]
  shared_credentials_files = ["/Users/evanwu/.aws/credentials"]
  profile                  = "e8wu"
}
