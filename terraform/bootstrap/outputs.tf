output "state_bucket_name" {
  description = "Put this in terraform/envs/*/backend.tf."
  value       = aws_s3_bucket.state.bucket
}

output "state_kms_key_arn" {
  description = "KMS key that encrypts Terraform state."
  value       = aws_kms_key.state.arn
}

output "github_oidc_provider_arn" {
  description = "Pass this to the env stacks (github_oidc_provider_arn) for the image-push role."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "terraform_plan_role_arn" {
  description = "Set as the AWS_PLAN_ROLE_ARN GitHub Actions variable."
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "Set as the AWS_APPLY_ROLE_ARN variable on each protected GitHub Environment."
  value       = aws_iam_role.terraform_apply.arn
}
