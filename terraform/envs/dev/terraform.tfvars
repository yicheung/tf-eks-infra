# Copy to terraform.tfvars (git-ignored) and fill in.

region            = "us-east-1"
project           = "parallel"
environment       = "dev"
github_repository = "yicheung/tf-eks-infra"
owner             = "yicheung"

# From `terraform -chdir=terraform/bootstrap output`
github_oidc_provider_arn = "arn:aws:iam::906754897253:oidc-provider/token.actions.githubusercontent.com"

# Who can reach the public API endpoint. Use your egress IP /32. [] = private only.
api_public_access_cidrs = ["108.41.8.224/32"]

# Must include the identity that runs Terraform.
#"arn:aws:iam::906754897253:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_abc123"
cluster_admin_principal_arns = [
  "arn:aws:iam::906754897253:role/tf-eks-infra-terraform-apply",
  "arn:aws:iam::906754897253:user/yicheung"
]

security_alert_emails = ["yicheung@yahoo.com"]

# Optional: public TLS for the sample app
# domain          = "dev.example.com"
# route53_zone_id = "Z0123456789ABCDEFGHIJ"
# acme_email      = "you@example.com"

enable_interface_endpoints = false
az_count = 2