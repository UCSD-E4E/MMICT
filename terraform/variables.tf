variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "mmict-aws-deployment"
}

variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "Development"
}

variable "rule_priority" {
  description = "Priority of the lifecycle policy rule"
  type        = number
  default     = 1
}
