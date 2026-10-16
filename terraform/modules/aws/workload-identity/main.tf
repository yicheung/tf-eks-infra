# Workload identity for EKS: one IAM role per Kubernetes ServiceAccount via
# EKS Pod Identity. No static keys, no node-role sharing, no IRSA annotations.
#
# The input shape (identities map keyed by name with namespace +
# service_account + permissions) is the cloud-neutral contract. The GKE
# implementation takes the same map and binds Google service accounts or IAM
# roles to Kubernetes ServiceAccounts with Workload Identity Federation.

module "pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.9"

  for_each = var.identities

  name            = "${var.cluster_name}-${each.key}"
  use_name_prefix = false
  description     = "Pod Identity for ${each.value.namespace}/${each.value.service_account}"

  # Presets for well-known controllers (policies maintained upstream)
  attach_aws_lb_controller_policy = each.value.aws_presets.lb_controller

  attach_external_secrets_policy        = length(each.value.aws_presets.external_secrets_secret_arns) > 0
  external_secrets_secrets_manager_arns = each.value.aws_presets.external_secrets_secret_arns
  external_secrets_kms_key_arns         = each.value.aws_presets.external_secrets_kms_key_arns
  external_secrets_create_permission    = false

  attach_cert_manager_policy    = length(each.value.aws_presets.cert_manager_hosted_zone_arns) > 0
  cert_manager_hosted_zone_arns = each.value.aws_presets.cert_manager_hosted_zone_arns

  attach_aws_cloudwatch_observability_policy = each.value.aws_presets.cloudwatch_observability

  # Anything custom
  attach_custom_policy   = length(each.value.policy_statements) > 0
  policy_statements      = length(each.value.policy_statements) > 0 ? each.value.policy_statements : null
  additional_policy_arns = { for i, arn in each.value.policy_arns : tostring(i) => arn }

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = each.value.namespace
      service_account = each.value.service_account
    }
  }

  tags = var.tags
}
