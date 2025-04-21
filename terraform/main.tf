terraform {
  backend "s3" {
    bucket         = "evan-tf-state-storage"
    key            = "state/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"  # optional for state locking
    profile = "e8wu"
  }
}

module "vpc" {
  source              = "./modules/vpc"
  project_name        = var.project_name
  aws_region = var.aws_region
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  private_route_table_id = module.networking.private_route_table_id
}

module "networking" {
  source              = "./modules/networking"
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids   = module.vpc.private_subnet_ids
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Define in secrets.tfvars file
variable "key_name" {}
variable "public_key_path" {}
variable "service_image_urls" {}

# Authentication during testing
resource "aws_key_pair" "my_key" {
  key_name = var.key_name
  #my public version of ssh key
  public_key = file(var.public_key_path)
}




resource "aws_instance" "app_server" {
  ami           = var.ecs_ami_id
  instance_type = "t4g.micro"

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
  /*
  network_interface {
    network_interface_id = module.networking.private_eni_id
    device_index         = 1
  }
  */


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
/*
data "aws_network_interfaces" "frontend_container_eni" {
  filter {
    name   = "tag:App"
    values = ["frontend"]
  }
}
data "aws_network_interface" "fe_details" {
  count = local.fe_eni_id != null ? 1 : 0
  id    = local.fe_eni_id
}
*/
data "aws_network_interfaces" "webserver_container_eni" {
  filter {
    name   = "tag:App"
    values = ["webserver"]
  }
}
data "aws_network_interface" "ws_details" {
  count = local.ws_eni_id != null ? 1 : 0
  id = local.ws_eni_id
}

locals {
  ws_alb_dns = aws_lb.webserver_alb.dns_name
  ec2_private_ip = aws_instance.app_server.private_ip
  eip_address = module.networking.my_eip_addresses[0]

  #fe_eni_id = try(data.aws_network_interfaces.frontend_container_eni.ids[0], null)
  #fe_eni_pub_ip = try(data.aws_network_interface.fe_details[0].association[0].public_ip, "0.0.0.0")
  ws_eni_id = try(data.aws_network_interfaces.webserver_container_eni.ids[0], null)
  ws_eni_priv_ip = local.ws_eni_id != null ? data.aws_network_interface.ws_details[0].private_ip : "0.0.0.0"

  services = {
    frontend = {
      port = 80
      essential = true
      env = [
        { name = "PORT", value = "80" },
        { name = "WEBSERVER_ADDRESS", value = "${local.ws_alb_dns}:3000"},
        { name = "REACT_APP_NGINX_ADDRESS", value = "${local.eip_address}"}
      ]
    }
    webserver = {
      port = 3000
      essential = true
      env = [
        { name = "PORT", value = "3000" },
        { name = "FRONTEND_ADDRESS", value = "${local.eip_address}:80"}
      ]
    }
  }
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
  for_each = local.services

  name = "/ecs/${var.project_name}-${each.key}"
  retention_in_days = 7
}

# Defines task blueprint. Specifies ECR repo and resources
resource "aws_ecs_task_definition" "mmict-frontend-task" {
  family             = "mmict-frontend-task"
  # network_mode = "awsvpc"
  # requires_compatibilities = ["EC2"]
  # cpu = "256"
  # memory = "256"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "frontend-container"
      image     = var.service_image_urls["frontend"]
      cpu       = 256
      memory    = 256
      essential = local.services["frontend"].essential

      environment = local.services["frontend"].env

      portMappings = [
        {
          containerPort = local.services["frontend"].port
          hostPort = local.services["frontend"].port
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.project_name}-frontend"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs-frontend"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "mmict-webserver-task" {
  family             = "mmict-webserver-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu = "256"
  memory = "256"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "webserver-container"
      image     = var.service_image_urls["webserver"]
      cpu       = 256
      memory    = 256
      essential = local.services["webserver"].essential

      environment = local.services["webserver"].env

      portMappings = [
        {
          containerPort = local.services["webserver"].port
          hostPort = local.services["webserver"].port
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.project_name}-webserver"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs-webserver"
        }
      }
    }
  ])
}


# Actually runs ECS tasks. Set desired_count=0 to stop tasks
resource "aws_ecs_service" "frontend-service" {
  name = "${var.project_name}-frontend-service"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mmict-frontend-task.arn
  desired_count = 1
  launch_type = "EC2"
  /*
  network_configuration {
    subnets = [module.vpc.public_subnet_ids[0]]
    security_groups = [module.networking.public_sg_id]
  }
  */
  /*
  propagate_tags = "SERVICE"
  tags = {
    "Name" = "frontend-task"
    "App"  = "frontend"
  }
  */

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent = 200
  # Relaunches task after any terraform apply
  force_new_deployment = true
}

resource "aws_ecs_service" "webserver-service" {
  name = "${var.project_name}-webserver-service"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mmict-webserver-task.arn
  desired_count = 1
  launch_type = "EC2"

  network_configuration {
    subnets = [module.vpc.private_subnet_ids[0]]
    security_groups = [module.networking.private_sg_id]
  }

  /*
  propagate_tags = "SERVICE"
  tags = {
    "Name" = "webserver-task"
    "App"  = "webserver"
  }
  */

  load_balancer {
    target_group_arn = aws_lb_target_group.webserver_tg.arn
    container_name = "webserver-container"
    container_port = 3000
  }

  # allow container to boot up/bind to ip port before ALB health checks
  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent = 200
  # Relaunches task after any terraform apply
  force_new_deployment = true
}



resource "aws_lb" "webserver_alb" {
  name = "webserver-alb"
  internal = true
  load_balancer_type = "application"
  subnets = module.vpc.private_subnet_ids
  security_groups = [module.networking.private_sg_id]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "webserver_tg" {
  name = "webserver-tg"
  port = 3000
  protocol = "HTTP"
  vpc_id = module.vpc.vpc_id

  target_type = "ip"

  health_check {
    path = "/"
    port = "3000"
    protocol = "HTTP"
    healthy_threshold = 2
    unhealthy_threshold = 3
    interval = 15
    timeout = 5
  }
}

resource "aws_lb_listener" "webserver_listener" {
  load_balancer_arn = aws_lb.webserver_alb.arn
  port = 3000
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.webserver_tg.arn
  }
}



resource "aws_s3_bucket" "b" {
  bucket = "tf-bucket-mangrove-test-12345"
}

# All objects in bucket owned by bucket owner
resource "aws_s3_bucket_ownership_controls" "b_controls" {
  bucket = aws_s3_bucket.b.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Only bucket owner and entities granted permission can access bucket
resource "aws_s3_bucket_acl" "b_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.b_controls]

  bucket = aws_s3_bucket.b.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "b_policy" {
  bucket = aws_s3_bucket.b.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowAccessFromVPC",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:*",
        Resource  = [
          "arn:aws:s3:::tf-bucket-mangrove-test-12345",
          "arn:aws:s3:::tf-bucket-mangrove-test-12345/*"
        ],
        Condition = {
          StringEquals = {
            "aws:SourceVpce" = "${module.vpc.s3_endpoint_id}"  # VPC Endpoint ID
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_versioning" "b_versioning" {
  bucket = aws_s3_bucket.b.id
  versioning_configuration {
    status = "Enabled"
  }
}

