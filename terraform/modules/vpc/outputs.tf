output "vpc_id" {
  description = "ID of VPC"
  value = aws_vpc.my_vpc.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value = aws_subnet.public_subnets[*].id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value = aws_subnet.private_subnet.id
}

output "s3_endpoint_id" {
  description = "S3 bucket endpoint id"
  value = aws_vpc_endpoint.s3_endpoint.id
}
