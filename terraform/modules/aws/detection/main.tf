# Runtime detection and logging on the AWS side.
#   - GuardDuty: EKS audit-log analysis + EKS Runtime Monitoring (agent managed
#     by GuardDuty as an EKS add-on)
#   - High-severity findings -> EventBridge -> SNS (email or chat)
#   - Container logs + Container Insights via the CloudWatch Observability
#     add-on, authenticated with Pod Identity
# In-cluster detection (Falco, Hubble) runs through GitOps; see platform/.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# GuardDuty
# ---------------------------------------------------------------------------
resource "aws_guardduty_detector" "this" {
  count  = var.create_guardduty_detector ? 1 : 0
  enable = true
  tags   = var.tags
}

locals {
  detector_id = var.create_guardduty_detector ? aws_guardduty_detector.this[0].id : var.existing_guardduty_detector_id
}

resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  detector_id = local.detector_id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  detector_id = local.detector_id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = "ENABLED"
  }
}

# ---------------------------------------------------------------------------
# Alert routing for findings with severity >= threshold
# ---------------------------------------------------------------------------
# A customer-managed key is required: EventBridge cannot publish to a topic
# encrypted with the AWS-managed aws/sns key.
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

  statement {
    sid       = "EventBridgePublish"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "${var.cluster_name} security alerts topic"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.alerts_kms.json
  tags                    = var.tags
}

resource "aws_sns_topic" "security_alerts" {
  name              = "${var.cluster_name}-security-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.cluster_name}-guardduty-findings"
  description = "GuardDuty findings at or above severity ${var.alert_min_severity}"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", var.alert_min_severity] }]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule = aws_cloudwatch_event_rule.guardduty_findings.name
  arn  = aws_sns_topic.security_alerts.arn
}

data "aws_iam_policy_document" "sns_events" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.guardduty_findings.arn]
    }
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn    = aws_sns_topic.security_alerts.arn
  policy = data.aws_iam_policy_document.sns_events.json
}

# ---------------------------------------------------------------------------
# Container logs: CloudWatch Observability add-on (Fluent Bit + agent)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_observability" {
  count              = var.enable_container_logs ? 1 : 0
  name               = "${var.cluster_name}-cloudwatch-observability"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  count      = var.enable_container_logs ? 1 : 0
  role       = aws_iam_role.cloudwatch_observability[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count                       = var.enable_container_logs ? 1 : 0
  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch_observability[0].arn
    service_account = "cloudwatch-agent"
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.cloudwatch_observability]
}
