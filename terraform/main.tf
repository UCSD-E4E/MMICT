# Provider block to define the AWS provider and configure the credentials and region
provider "aws" {
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Fetch account ID dynamically
data "aws_caller_identity" "current" {}

# VPC Module
module "vpc" {
  source              = "./modules/vpc"
  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidr = var.private_subnet_cidr
}

# Networking Module
module "networking" {
  source              = "./modules/networking"
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_id   = module.vpc.private_subnet_id
  public_subnet_cidrs = var.public_subnet_cidrs
}

# EC2 Instance
resource "aws_instance" "app_server" {
  ami           = "ami-08d70e59c07c61a3a"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.my_key.key_name

  user_data = <<-EOF
    #!/bin/bash
    cd /home/ubuntu
    git clone https://github.com/TWintersww/dummy-repo.git
  EOF

  network_interface {
    network_interface_id = module.networking.public_eni_ids[0]
    device_index         = 0
  }
  network_interface {
    network_interface_id = module.networking.private_eni_id
    device_index         = 1
  }

  tags = {
    Name = "MyEC2Instance"
  }
}

# SSH Key Pair
resource "aws_key_pair" "my_key" {
  key_name   = "aws_first_key"
  public_key = file("~/.ssh/aws_first.pub")
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# IAM Role for EC2 Instance
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# Launch Template
resource "aws_launch_template" "ecs_instance" {
  name_prefix   = "${var.project_name}-ecs-instance"
  image_id      = var.ecs_ami_id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups            = [module.networking.public_sg_id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-ecs-instance"
    }
  }
}

# S3 Bucket
resource "aws_s3_bucket" "b" {
  bucket = "tf-bucket-vivian-test-846248"
}

resource "aws_s3_bucket_ownership_controls" "b" {
  bucket = aws_s3_bucket.b.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "b" {
  depends_on = [aws_s3_bucket_ownership_controls.b]
  bucket     = aws_s3_bucket.b.id
  acl        = "private"
}

resource "aws_s3_bucket_versioning" "b" {
  bucket = aws_s3_bucket.b.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ECR Repository
resource "aws_ecr_repository" "mmict-ecr-repo" {
  name                 = "mmict-ecr-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "mmict-ecr-repo"
    Environment = var.environment
  }

  lifecycle {
    prevent_destroy = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ECR IAM Policy
resource "aws_iam_policy" "ecr_policy" {
  name        = "ecr_push_pull_policy"
  description = "Policy for pushing and pulling from ECR"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/mmict-ecr-repo"
      }
    ]
  })
}