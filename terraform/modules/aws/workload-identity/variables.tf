variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "identities" {
  description = <<-EOT
    Map of workload identities. Each entry binds exactly one Kubernetes
    ServiceAccount to one IAM role.

      namespace / service_account : the Kubernetes subject
      policy_statements           : custom least-privilege IAM statements
      policy_arns                 : managed policies to attach (use sparingly)
      aws_presets                 : upstream-maintained policies for common controllers
  EOT
  type = map(object({
    namespace       = string
    service_account = string
    policy_statements = optional(list(object({
      sid       = optional(string)
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      condition = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })))
    })), [])
    policy_arns = optional(list(string), [])
    aws_presets = optional(object({
      lb_controller                 = optional(bool, false)
      external_secrets_secret_arns  = optional(list(string), [])
      external_secrets_kms_key_arns = optional(list(string), [])
      cert_manager_hosted_zone_arns = optional(list(string), [])
      cloudwatch_observability      = optional(bool, false)
    }), {})
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
