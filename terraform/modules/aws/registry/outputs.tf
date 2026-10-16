output "registry_host" {
  description = "ECR registry hostname, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}

output "repository_urls" {
  description = "Repository URL per name."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "ci_push_role_arn" {
  description = "Set as the AWS_IMAGE_PUSH_ROLE_ARN GitHub Actions variable."
  value       = aws_iam_role.ci_push.arn
}
