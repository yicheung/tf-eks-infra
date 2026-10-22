# Fill in from `terraform -chdir=terraform/bootstrap output`.
# S3-native locking (use_lockfile) replaces the DynamoDB lock table.
terraform {
  backend "s3" {
    bucket       = "tf-eks-infra-tfstate-906754897253-us-east-1"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
