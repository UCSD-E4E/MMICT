variable "project_name" {
  type    = string
  default = "mmict-aws-deployment"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnets"
  type        = string
  default     = "10.0.3.0/24"
}





variable "ecs_ami_id" {
  description = "AMI ID for ECS instances"
  type        = string
  default     = "amzn2-ami-ecs-kernel-5.10-hvm-2.0.20250117-x86_64-ebs"
  # You'll need to specify the ECS-optimized AMI ID for your region
  # Find it here: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 1
}
