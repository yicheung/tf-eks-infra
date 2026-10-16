variable "repo_url" {
  description = "Git URL Argo CD syncs from (this repo)."
  type        = string
}

variable "target_revision" {
  description = "Branch, tag or commit Argo CD tracks."
  type        = string
  default     = "main"
}

variable "cluster_values" {
  description = <<-EOT
    Cloud-specific values handed to platform/bootstrap. Required key: `cloud`
    ("eks" or "gke"). The EKS env passes clusterName, region, accountId, vpcId,
    registry host, signer identity, etc. See platform/bootstrap/values.yaml.
  EOT
  type        = any

  validation {
    condition     = contains(["eks", "gke"], try(var.cluster_values.cloud, ""))
    error_message = "cluster_values.cloud must be \"eks\" or \"gke\"."
  }
}

variable "platform_chart_repos" {
  description = "Helm repositories the platform AppProject may pull charts from."
  type        = list(string)
  default = [
    "https://charts.jetstack.io",
    "https://charts.external-secrets.io",
    "https://kyverno.github.io/kyverno",
    "https://falcosecurity.github.io/charts",
    "https://aws.github.io/eks-charts",
  ]
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "10.10.5"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version."
  type        = string
  default     = "2.0.6"
}

variable "argocd_admin_enabled" {
  description = "Keep the local admin user. Set false after SSO is configured."
  type        = bool
  default     = true
}

variable "argocd_rbac_policy_csv" {
  description = "Argo CD RBAC policy.csv (map SSO groups to roles)."
  type        = string
  default     = ""
}
