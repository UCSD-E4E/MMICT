# EIP to attach to FE task for testing purposes
resource "aws_eip" "frontend_task_eip" {
  domain   = "vpc"

  tags = {
    Name = "frontend-task-eip"
  }
}


resource "aws_security_group" "public_sg" {
  name        = "public-sg"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80 # HTTP. Anyone on internet can connect
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow port 80 from itself (for ALB health check ping to FE task)
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    self = true
  }

  /*
  ingress {
    from_port   = 32768 
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  */

  #FOR TESTING
  ingress {
    from_port   = 22 # SSH
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Could potentially tighten to only port 3000 for tcp protocol if FE only comms with WS and no other apis
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_sg" {
  name        = "private-sg"
  vpc_id      = var.vpc_id

  # Incoming traffic on port 3000 allowed only from resources associated with public_sg
  # 3000 defined as WS port
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    security_groups = [aws_security_group.public_sg.id] # Allow traffic from public ENI
  }

  # Allow port 3000 from itself (for ALB health check ping to WS task)
  ingress {
    from_port = 3000
    to_port = 3000
    protocol = "tcp"
    self = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id      = var.vpc_id
  tags = {
    Name = "MyInternetGateway"
  }
}

resource "aws_eip" "nat_eip" {
  count = length(var.public_subnet_cidrs)
  domain = "vpc"
}
# nat_gw is subnet specific, so need multiple
resource "aws_nat_gateway" "nat_gw" {
  count = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id = var.public_subnet_ids[count.index]
}

resource "aws_route" "private_nat_route" {
  count = length(var.private_subnet_cidrs)
  route_table_id = aws_route_table.private_route_table[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat_gw[count.index].id
}

resource "aws_route_table" "public_route_table" {
  vpc_id      = var.vpc_id
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
  count = length(var.public_subnet_cidrs)
  subnet_id = var.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  count = length(var.private_subnet_cidrs)
  vpc_id = var.vpc_id
  tags = {
    Name = "PrivateRouteTable-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  count = length(var.private_subnet_cidrs)
  subnet_id = var.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private_route_table[count.index].id
}


