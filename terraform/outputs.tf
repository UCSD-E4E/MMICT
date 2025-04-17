output "vpc_id" {
  description = "ID of VPC"
  value       = module.vpc.vpc_id
}

output "eip_address" {
  value = module.networking.my_eip_addresses[0]
}
