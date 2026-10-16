variable "name_prefix" {
  description = "Prefix for repository names (repos are <prefix>/<name>)."
  type        = string
}

variable "repositories" {
  description = "Repository names to create under the prefix."
  type        = list(string)
  default     = ["sample-app"]
}

variable "enable_enhanced_scanning" {
  description = "Turn on registry-wide Amazon Inspector enhanced scanning (billed per image scanned)."
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN (output of terraform/bootstrap)."
  type        = string
}

variable "github_repository" {
  description = "owner/name of the repo whose main branch may push images."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
