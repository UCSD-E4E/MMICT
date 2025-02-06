output "public_eni_ids" {
  value = aws_network_interface.public_eni[*].id
}

output "private_eni_id" {
  value = aws_network_interface.private_eni.id
}

output "public_sg_id" {
  value = aws_security_group.public_sg.id
}
