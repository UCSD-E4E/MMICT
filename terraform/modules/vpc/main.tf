resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr #custom ip range of 256
  #allows resolution of domain names via DNS
  enable_dns_support = true
  #gives public DNS hostnames to instances with public IPs
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.my_vpc.id
  service_name = "com.amazonaws.us-west-2.s3"
  route_table_ids = [aws_vpc.my_vpc.default_route_table_id]
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index] 
  # provides public ip for ec2 instance on launch
  # SET TO FALSE, b/c this field is overriden to false when we
  # use network_interface in ec2 instance. Manually create elastic ip instead
  map_public_ip_on_launch = false
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = var.private_subnet_cidr
  availability_zone = aws_subnet.public_subnets[0].availability_zone
  tags = {
    Name = "${var.project_name}-private-1"
  }
}
