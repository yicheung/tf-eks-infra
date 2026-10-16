terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }

  # Bootstrap starts with local state. After the first apply, either uncomment
  # this block or (as docs/TF-init-deployment.md does) put the same block in a
  # separate backend.tf, then run `terraform init -migrate-state` to move the
  # state into the bucket it just created. Only one backend block may exist.
  # backend "s3" {
  #   bucket       = "<state_bucket_name output>"
  #   key          = "bootstrap/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
