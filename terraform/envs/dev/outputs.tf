output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Configure kubectl."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "argocd_ui_command" {
  description = "Reach Argo CD."
  value       = module.platform.argocd_ui_command
}

output "ecr_repository_urls" {
  description = "Image repositories."
  value       = module.registry.repository_urls
}

output "ci_image_push_role_arn" {
  description = "Set as the AWS_IMAGE_PUSH_ROLE_ARN GitHub Actions variable."
  value       = module.registry.ci_push_role_arn
}

output "workload_role_arns" {
  description = "IAM role per workload identity."
  value       = module.workload_identity.role_arns
}

output "control_plane_log_group" {
  description = "Audit and control-plane logs."
  value       = module.eks.control_plane_log_group
}

output "security_alerts_topic_arn" {
  description = "SNS topic for GuardDuty (and optionally Falco) alerts."
  value       = module.detection.security_alerts_topic_arn
}
