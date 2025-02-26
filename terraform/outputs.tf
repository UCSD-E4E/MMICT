output "vpc_id" {
  description = "ID of VPC"
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.mmict-ecr-repo.repository_url
}
