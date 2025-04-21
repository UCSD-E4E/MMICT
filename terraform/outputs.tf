output "vpc_id" {
  description = "ID of VPC"
  value       = module.vpc.vpc_id
}

output "ec2_eip_address" {
  value = module.networking.my_eip_addresses[0]
}
/*
output "fe_eni_pub_ip" {
  value = local.fe_eni_pub_ip
  description = "Public IP address of the frontend container ENI"
}
*/
output "ws_eni_priv_ip" {
  value       = local.ws_eni_priv_ip
  description = "Private IP address of the webserver container ENI"
}
