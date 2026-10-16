# These outputs form the cluster contract shared with the GKE module (see
# docs/adding-gke.md): name, endpoint, CA, and an identity hook.

output "cluster_name" {
  description = "Cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (https URL)."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Kubernetes version."
  value       = module.eks.cluster_version
}

output "node_security_group_id" {
  description = "Security group shared by nodes (and, in Cilium ENI mode, pods)."
  value       = module.eks.node_security_group_id
}

output "node_iam_role_name" {
  description = "Node IAM role name."
  value       = module.eks.node_iam_role_name
}

output "secrets_kms_key_arn" {
  description = "KMS key used for Kubernetes secrets envelope encryption."
  value       = module.eks.kms_key_arn
}

output "control_plane_log_group" {
  description = "CloudWatch log group with control-plane and audit logs."
  value       = module.eks.cloudwatch_log_group_name
}
