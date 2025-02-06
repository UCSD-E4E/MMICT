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






resource "aws_instance" "app_server" {
  #This instance is x86. Use command "uname -m" to check
  ami           = "ami-08d70e59c07c61a3a"
  instance_type = "t2.micro"

  #iam_instance_profile = #aws_iam_instance_profile.ecs_instance_profile.name
  /* add this in ecs outputs
  output "ecs_instance_profile_name" {
    description = "Name of the ECS instance profile"
    value       = aws_iam_instance_profile.ecs_instance_profile.name
  }
  */

  key_name = aws_key_pair.my_key.key_name

  #script runs on instance creation
  user_data = <<-EOF
    #!/bin/bash

    #user_data scripts run as root by default
    cd /home/ubuntu

    #install docker
    #sudo apt update -y

    #sudo apt install -y docker.io
    #sudo systemctl start docker
    #sudo systemctl enable docker
    #sudo usermod -aG docker ubuntu



    # git clone dummy repo
    git clone https://github.com/TWintersww/dummy-repo.git
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

resource "aws_key_pair" "my_key" {
  key_name = "aws_first_key"
  #my public version of aws_first ssh key
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
  image_id      = var.ecs_ami_id # Amazon ECS-Optimized AMI ID
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    #security_groups            = [aws_security_group.ecs_instance.id]
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

# Auto Scaling Group
resource "aws_autoscaling_group" "ecs_instances" {
  name                = "${var.project_name}-ecs-asg"
  #vpc_zone_identifier = aws_subnet.public[*].id
  vpc_zone_identifier = module.vpc.public_subnet_ids
  target_group_arns   = []
  health_check_type   = "EC2"
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  min_size            = var.min_size

  launch_template {
    id      = aws_launch_template.ecs_instance.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-instance"
    propagate_at_launch = true
  }
}

# Capacity Provider
resource "aws_ecs_capacity_provider" "main" {
  name = "${var.project_name}-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_instances.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                   = "ENABLED"
      target_capacity          = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = [aws_ecs_capacity_provider.main.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.main.name
  }
}







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

  bucket = aws_s3_bucket.b.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "b" {
  bucket = aws_s3_bucket.b.id
  versioning_configuration {
    status = "Enabled"
  }
}
