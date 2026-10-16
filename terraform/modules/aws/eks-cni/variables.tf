variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint (https URL). Cilium talks to it directly because kube-proxy is not installed."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. Traffic inside it is natively routed; everything else is masqueraded."
  type        = string
}

variable "cilium_version" {
  description = "Cilium Helm chart version."
  type        = string
  default     = "1.20.3"
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
