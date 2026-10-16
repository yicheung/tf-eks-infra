output "role_arns" {
  description = "IAM role ARN per identity."
  value       = { for k, m in module.pod_identity : k => m.iam_role_arn }
}
