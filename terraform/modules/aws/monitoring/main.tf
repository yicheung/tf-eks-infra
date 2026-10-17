# AWS side of platform monitoring:
#   - SNS topic for operational alerts from Alertmanager (separate from the
#     security-alerts topic so on-call noise and security findings don't mix)
#   - Pod Identity role that lets Alertmanager publish to it
# Prometheus, Alertmanager and Grafana themselves are deployed by Argo CD
# (platform/values/kube-prometheus-stack).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "alerts_kms" {
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "${var.cluster_name} platform alerts topic"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.alerts_kms.json
  tags                    = var.tags
}

resource "aws_sns_topic" "platform_alerts" {
  name              = "${var.cluster_name}-platform-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.platform_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

module "alertmanager_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.9"

  name            = "${var.cluster_name}-alertmanager"
  use_name_prefix = false
  description     = "Alertmanager -> SNS platform alerts"

  attach_custom_policy = true
  policy_statements = [
    {
      sid       = "PublishAlerts"
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.platform_alerts.arn]
    },
    {
      sid       = "EncryptAlerts"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
      resources = [aws_kms_key.alerts.arn]
    },
  ]

  associations = {
    alertmanager = {
      cluster_name    = var.cluster_name
      namespace       = var.namespace
      service_account = var.alertmanager_service_account
    }
  }

  tags = var.tags
}
