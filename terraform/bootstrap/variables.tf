variable "project" {
  description = "Short project name used as a prefix for every resource."
  type        = string
  default     = "tf-eks-infra"
}

variable "region" {
  description = "AWS region for the state bucket and the CI roles."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name."
  type        = string
  default     = "yicheung/tf-eks-infra"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the owner/name form, e.g. yicheung/tf-eks-infra."
  }
}

variable "apply_environments" {
  description = "GitHub Environments whose jobs may assume the apply role. Protect these with required reviewers."
  type        = list(string)
  default     = ["dev"]
}

variable "apply_role_policy_arns" {
  description = "Managed policies attached to the Terraform apply role. AdministratorAccess is a starting point; replace it with a scoped policy plus a permissions boundary before production."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}
