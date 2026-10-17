variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "namespace" {
  description = "Namespace kube-prometheus-stack runs in."
  type        = string
  default     = "monitoring"
}

variable "alertmanager_service_account" {
  description = "Alertmanager ServiceAccount name (set in platform/values/kube-prometheus-stack/common.yaml)."
  type        = string
  default     = "alertmanager"
}

variable "alert_emails" {
  description = "Email addresses subscribed to platform (operational) alerts."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
