variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version. Stay within EKS standard support."
  type        = string
  default     = "1.36"
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "node_subnet_ids" {
  description = "Private subnets for nodes and pod ENIs."
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Intra subnets for the EKS control-plane ENIs."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Empty list = private endpoint only (Terraform and kubectl must then run from inside the VPC or over VPN)."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "Do not open the Kubernetes API to 0.0.0.0/0. List admin/CI egress CIDRs, or leave empty for private-only."
  }
}

variable "access_entries" {
  description = "EKS access entries (IAM principal -> Kubernetes permissions). See the eks module docs for the shape."
  type        = any
  default     = {}
}

variable "node_groups" {
  description = "Managed node groups. Bottlerocket by default."
  type = map(object({
    ami_type       = optional(string, "BOTTLEROCKET_x86_64")
    instance_types = optional(list(string), ["m7i.large"])
    capacity_type  = optional(string, "ON_DEMAND")
    min_size       = optional(number, 2)
    max_size       = optional(number, 4)
    desired_size   = optional(number, 2)
    disk_size_gb   = optional(number, 40)
    labels         = optional(map(string), {})
    taints = optional(map(object({
      key    = string
      value  = optional(string)
      effect = string
    })), {})
  }))
  default = {
    system = {}
  }
}

variable "control_plane_log_types" {
  description = "EKS control-plane log types sent to CloudWatch. [] disables control-plane logging."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition     = alltrue([for t in var.control_plane_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "Valid log types: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "log_retention_days" {
  description = "Retention for control-plane logs."
  type        = number
  default     = 365
}

variable "log_kms_key_arn" {
  description = "KMS key ARN for the control-plane log group."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Block cluster deletion through the API."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
