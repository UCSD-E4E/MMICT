resource "aws_network_interface" "public_eni" {
  count = length(var.public_subnet_cidrs)
  subnet_id = var.public_subnet_ids[count.index]
  description = "Public ENI for Frontend ${count.index + 1}"
  security_groups = [aws_security_group.public_sg.id]
}

resource "aws_network_interface" "private_eni" {
  subnet_id = var.private_subnet_id
  description = "Private ENI for Webserver"
  security_groups = [aws_security_group.private_sg.id]
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

  ingress {
    from_port   = 32768 
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #FOR TESTING
  ingress {
    from_port   = 22 # SSH
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
  vpc_id      = var.vpc_id

  # Incoming traffic on port 3000 allowed only from resources associated with public_sg
  # 3000 defined as WS port
  ingress {
    from_port   = 3000
    to_port     = 3000
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
  vpc_id      = var.vpc_id
  tags = {
    Name = "MyInternetGateway"
  }
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
  vpc_id = var.vpc_id
  tags = {
    Name = "PrivateRouteTable"
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id = var.private_subnet_id
  route_table_id = aws_route_table.private_route_table.id
}


resource "aws_eip" "my_eip" {
  count = length(aws_network_interface.public_eni)
  tags = {
    Name = "MyElasticIP-${count.index + 1}"
  }
}

resource "aws_eip_association" "my_eip_assoc" {
  count = length(aws_network_interface.public_eni)
  allocation_id = aws_eip.my_eip[count.index].id
  network_interface_id = aws_network_interface.public_eni[count.index].id
}
