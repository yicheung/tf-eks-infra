terraform {
  backend "s3" {
    bucket       = "tf-eks-infra-tfstate-906754897253-us-east-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}