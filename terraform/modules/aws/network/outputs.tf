output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Subnets for worker nodes and pod ENIs."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Subnets for internet-facing load balancers."
  value       = module.vpc.public_subnets
}

output "intra_subnet_ids" {
  description = "Subnets for EKS control-plane ENIs."
  value       = module.vpc.intra_subnets
}
