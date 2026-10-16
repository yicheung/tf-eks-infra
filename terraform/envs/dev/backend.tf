# Fill in from `terraform -chdir=terraform/bootstrap output`.
# S3-native locking (use_lockfile) replaces the DynamoDB lock table.
terraform {
  backend "s3" {
    bucket       = "REPLACE_WITH_state_bucket_name"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
