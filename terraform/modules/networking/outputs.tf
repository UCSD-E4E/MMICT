output "public_sg_id" {
  value = aws_security_group.public_sg.id
}

output "private_sg_id" {
  value = aws_security_group.private_sg.id
}

output "private_route_table_ids" {
  value = [for rt in aws_route_table.private_route_table : rt.id]
}
