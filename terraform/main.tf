# Provider block to define the AWS provider and configure the credentials and region
provider "aws" {
  region = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Fetch account ID dynamically
data "aws_caller_identity" "current" {}

# Resource block to create an Amazon ECR Repo
resource "aws_ecr_repository" "mmict-ecr-repo" {
  name                 = "mmict-ecr-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    "Name"        = "mmict-ecr-repo"
    "Environment" = var.environment
  }

  lifecycle {
    prevent_destroy = true
  }

  image_encryption_configuration {
    encryption_type = "AES256"
  }
}

# Resource block to define a lifecycle policy for managing images in the ECR repository
resource "aws_ecr_lifecycle_policy" "my_lifecycle_policy" {
  repository = aws_ecr_repository.mmict-ecr-repo.name

  lifecycle_policy {
    rule {
      rule_priority = var.rule_priority
      description   = "Expire images older than 30 days"
      status        = "Enabled"
      action {
        type = "expire"
      }
      filter {
        tag_status = "any"
        tag {
          value = "*"
        }
      }
      image_expiry {
        days = 30
      }
    }
  }
}

# Resource block to define an IAM policy that allows pushing and pulling images from the ECR repository
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
          "ecr:PutImage",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/mmict-ecr-repo"
      },
    ]
  })
}

# IAM Role for ECS Task to access ECR
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policy to ECS task execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecr_policy.arn
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Add IAM Role to ECS Task Definitions to pull images from ECR
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-task"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "my-container"
    image     = "${aws_ecr_repository.mmict-ecr-repo.repository_url}:latest"
    cpu       = 256
    memory    = 512
    essential = true
  }])
}
