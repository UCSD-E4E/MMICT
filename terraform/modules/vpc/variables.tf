variable "project_name" {
  type        = string
}

variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR block for private subnets"
  type        = list(string)
}

variable "private_route_table_id" {
  description = "Private route table id for vpc endpoint for s3 bucket"
  type = string
}

