module "vpc" {
  source              = "./modules/vpc"
  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidr = var.private_subnet_cidr
}

module "networking" {
  source              = "./modules/networking"
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_id   = module.vpc.private_subnet_id
  public_subnet_cidrs = var.public_subnet_cidrs
}

# Define in secrets.tfvars file
variable "key_name" {}
variable "public_key_path" {}

# Authentication during testing
resource "aws_key_pair" "my_key" {
  key_name = var.key_name
  #my public version of ssh key
  public_key = file(var.public_key_path)
}




resource "aws_instance" "app_server" {
  #This instance is x86. Use command "uname -m" to check
  ami           = var.ecs_ami_id
  instance_type = "t2.micro"

  iam_instance_profile = aws_iam_instance_profile.ecs_instance_profile.name

  key_name = aws_key_pair.my_key.key_name

  #script runs on instance creation
  user_data = <<-EOF
    #!/bin/bash

    sleep 20
    
    echo "ECS_CLUSTER=${var.project_name}-cluster" | sudo tee /etc/ecs/ecs.config

    #force docker to restart ecs-agent
    sudo docker run --name ecs-agent --detach --restart=on-failure \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /var/log/ecs:/log \
      -v /var/lib/ecs/data:/data \
      -e ECS_CLUSTER=${var.project_name}-cluster \
      amazon/amazon-ecs-agent:latest
  EOF

  #attach each both ENIs to instance
  #b/c ENI already attached to subnet, instance's subnet_id is implicitly determined
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



# Fetch account ID dynamically
data "aws_caller_identity" "current" {
}

resource "aws_ecr_repository" "mmict-ecr-repo" {
  name                 = "${var.project_name}-ecr"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    "Name"        = "${var.project_name}-ecr"
    "Environment" = "production"
  }

  lifecycle {
    prevent_destroy = true
  }

  encryption_configuration {
    encryption_type = "AES256" # Correct block for encryption configuration
  }
}

resource "aws_ecr_lifecycle_policy" "my_lifecycle_policy" {
  repository = aws_ecr_repository.mmict-ecr-repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire images older than 30 days if not tagged"
        action = {
          type = "expire"
        }
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 30
        }
      },
      {
        rulePriority = 2
        description   = "Do not expire the latest tagged images"
        action = {
          type = "expire"
        }
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 1
        }
      }
    ]
  })
}

# IAM policy defined for specific user/role/group
resource "aws_iam_policy" "ecr_policy" {
  name        = "ecr_push_pull_policy"
  description = "Policy for pushing and pulling from ECR"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# IAM role for ECS tasks
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

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecr_policy.arn
}

resource "aws_cloudwatch_log_group" "ecs_my_service" {
  name = "/ecs/my-service"
  retention_in_days = 7
}

# Defines task blueprint. Specifies ECR repo and resources
resource "aws_ecs_task_definition" "main" {
  family             = "${var.project_name}-task"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "my-container"
    image     = "${aws_ecr_repository.mmict-ecr-repo.repository_url}:latest"
    cpu       = 256
    memory    = 512
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/my-service"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# Actually runs ECS tasks. Set desired_count=0 to stop tasks
resource "aws_ecs_service" "my_service" {
  name = "${var.project_name}-service"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count = 0
  launch_type = "EC2"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent = 200

  # Relaunches task after any terraform apply
  force_new_deployment = true
}




resource "aws_s3_bucket" "b" {
  bucket = "tf-bucket-mangrove-test-12345"
}

resource "aws_s3_bucket_ownership_controls" "b" {
  bucket = aws_s3_bucket.b.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "b" {
  depends_on = [aws_s3_bucket_ownership_controls.b]

  bucket = aws_s3_bucket.b.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "b" {
  bucket = aws_s3_bucket.b.id
  versioning_configuration {
    status = "Enabled"
  }
}
