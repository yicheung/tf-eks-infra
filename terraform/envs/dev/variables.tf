variable "project" {
  description = "Project name; prefixes most resources."
  type        = string
  default     = "tf-eks-infra"
}

variable "owner" {
  description = "Owner of the project"
  type        = string
  default     = "admin"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "owner/name of this repository (for CI trust and Argo CD)."
  type        = string
  default     = "yicheung/tf-eks-infra"
}

variable "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN from terraform/bootstrap."
  type        = string
}

# --- Network -------------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC CIDR (/16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Availability zones."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "One NAT gateway for the VPC (dev) instead of one per AZ."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Interface VPC endpoints for AWS APIs."
  type        = bool
  default     = true
}

# --- Cluster ---------------------------------------------------------------------
variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "api_public_access_cidrs" {
  description = "CIDRs allowed to the public API endpoint (your IP, CI egress). Empty = private only."
  type        = list(string)
}

variable "cluster_admin_principal_arns" {
  description = "IAM role ARNs with cluster-admin. MUST include whatever identity runs Terraform (e.g. the terraform-apply role and your SSO admin role)."
  type        = list(string)

  validation {
    condition     = length(var.cluster_admin_principal_arns) > 0
    error_message = "List at least one admin principal, or Terraform will lose access to the cluster it creates."
  }
}

variable "cluster_viewer_principal_arns" {
  description = "IAM role ARNs with read-only cluster access."
  type        = list(string)
  default     = []
}

variable "node_groups" {
  description = "Managed node groups (see modules/aws/eks for the shape)."
  type        = any
  default = {
    system = {}
  }
}

variable "cilium_version" {
  description = "Cilium chart version."
  type        = string
  default     = "1.20.3"
}

variable "deletion_protection" {
  description = "EKS deletion protection."
  type        = bool
  default     = false
}

variable "control_plane_log_types" {
  description = "EKS control-plane log types to CloudWatch. Keep at least audit + authenticator; [] turns control-plane logging off."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition     = alltrue([for t in var.control_plane_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "Valid log types: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "enable_flow_logs" {
  description = "VPC flow logs to CloudWatch."
  type        = bool
  default     = true
}

variable "enable_container_logs" {
  description = "CloudWatch Observability add-on (container logs + Container Insights)."
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Prometheus, Alertmanager and Grafana (plus the EBS CSI driver, encrypted StorageClass and platform-alerts SNS topic they use)."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch retention for flow and control-plane logs."
  type        = number
  default     = 365
}

# --- Supply chain ------------------------------------------------------------------
variable "ecr_repositories" {
  description = "ECR repositories to create (under <project>/)."
  type        = list(string)
  default     = ["sample-app"]
}

# --- Detection -------------------------------------------------------------------------
variable "create_guardduty_detector" {
  description = "Create the GuardDuty detector (false if your org already enabled it)."
  type        = bool
  default     = true
}

variable "existing_guardduty_detector_id" {
  description = "Existing detector ID when create_guardduty_detector = false."
  type        = string
  default     = null
}

variable "security_alert_emails" {
  description = "Emails for high-severity security alerts."
  type        = list(string)
  default     = []
}

variable "platform_alert_emails" {
  description = "Emails for operational alerts from Alertmanager (separate from security alerts)."
  type        = list(string)
  default     = []
}

# --- Ingress / TLS -------------------------------------------------------------------------
variable "domain" {
  description = "Base domain for public hostnames (e.g. dev.example.com). Leave null to skip TLS issuance."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for cert-manager DNS-01. Null disables the cert-manager identity and issuer."
  type        = string
  default     = null
}

variable "acme_email" {
  description = "Contact email for Let's Encrypt."
  type        = string
  default     = null
}

variable "acme_use_staging" {
  description = "Use the Let's Encrypt staging endpoint (untrusted certs, no rate limits)."
  type        = bool
  default     = true
}

# --- GitOps ------------------------------------------------------------------------------------
variable "gitops_target_revision" {
  description = "Branch/tag Argo CD tracks."
  type        = string
  default     = "main"
}
