# Persistent volumes for platform components (Prometheus, Alertmanager).
#   - EBS CSI driver as an EKS add-on, authenticated with EKS Pod Identity
#   - Customer-managed KMS key; every volume the driver creates is encrypted
#     with it (the StorageClass is declared in GitOps: platform/bootstrap)
# GKE equivalent: the Persistent Disk CSI driver is built in; only a CMEK key
# and StorageClass are needed.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "ebs_kms" {
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

resource "aws_kms_key" "ebs" {
  description             = "${var.cluster_name} EBS volumes (CSI)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.ebs_kms.json
  tags                    = var.tags
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.cluster_name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# IAM role only; the association is created by the add-on below.
module "ebs_csi_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.9"

  name            = "${var.cluster_name}-ebs-csi"
  use_name_prefix = false
  description     = "EBS CSI controller"

  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = [aws_kms_key.ebs.arn]

  tags = var.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = module.ebs_csi_identity.iam_role_arn
    service_account = "ebs-csi-controller-sa"
  }

  tags = var.tags
}
