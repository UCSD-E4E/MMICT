terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/24" #custom ip range of 256
  #allows resolution of domain names via DNS
  enable_dns_support = true
  #gives public DNS hostnames to instances with public IPs
  enable_dns_hostnames = true
  tags = {
    Name = "MyVPC"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "10.0.0.0/25" #first half of vpc
  # provides public ip for ec2 instance on launch
  # SET TO FALSE, b/c this field is overriden to false when we
  # use network_interface in ec2 instance. Manually create elastic ip instead
  map_public_ip_on_launch = false
  availability_zone = "us-west-2a"
  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "10.0.0.128/25" #second half of vpc
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet"
  }
}

resource "aws_network_interface" "public_eni" {
  subnet_id = aws_subnet.public_subnet.id
  description = "Public ENI for Frontend"
  security_groups = [aws_security_group.public_sg.id]
}

resource "aws_network_interface" "private_eni" {
  subnet_id = aws_subnet.private_subnet.id
  description = "Private ENI for Webserver"
  security_groups = [aws_security_group.private_sg.id]
}


resource "aws_security_group" "public_sg" {
  name        = "public-sg"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #allow ssh from specific cidr blocks. format: "<your-ip>/32"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["128.54.161.255/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "private_sg" {
  name        = "private-sg"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.public_sg.id] # Allow traffic from public ENI
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "MyInternetGateway"
  }
}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    # for outgoing traffic to the internet
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}


resource "aws_eip" "my_eip" {
  tags = {
    Name = "MyElasticIP"
  }
}
resource "aws_eip_association" "my_eip_assoc" {
  allocation_id = aws_eip.my_eip.id
  network_interface_id = aws_network_interface.public_eni.id
}

resource "aws_instance" "app_server" {
  #This instance is x86. Use command "uname -m" to check
  ami           = "ami-08d70e59c07c61a3a"
  instance_type = "t2.micro"
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


    # git clone dummy repo
    git clone https://github.com/TWintersww/dummy-repo.git
  EOF

  #attach each both ENIs to instance
  #b/c ENI already attached to subnet, instance's subnet_id is implicitly determined
  network_interface {
    network_interface_id = aws_network_interface.public_eni.id
    device_index         = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.private_eni.id
    device_index         = 1
  }
  

  tags = {
    Name = var.instance_name
  }
}

resource "aws_key_pair" "my_key" {
  key_name = "aws_first_key"
  #my public version of aws_first ssh key
  public_key = file("~/.ssh/aws_first.pub")
}
