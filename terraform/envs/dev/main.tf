# dev environment on AWS: network -> EKS -> CNI -> identities/registry/detection
# -> GitOps hand-off. A GKE env would swap the modules/aws/* calls for
# modules/gcp/* and keep platform-bootstrap and everything under platform/.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = var.github_repository
  }

  cluster_admin_entries = {
    for i, arn in var.cluster_admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  cluster_viewer_entries = {
    for i, arn in var.cluster_viewer_principal_arns : "viewer-${i}" => {
      principal_arn = arn
      policy_associations = {
        view = {
          policy_arn   = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Network segmentation (VPC layer)
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/aws/network"

  name                       = local.name
  vpc_cidr                   = var.vpc_cidr
  az_count                   = var.az_count
  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  log_kms_key_arn            = aws_kms_key.logs.arn
  log_retention_days         = var.log_retention_days
  tags                       = local.tags
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
module "eks" {
  source = "../../modules/aws/eks"

  cluster_name             = local.name
  kubernetes_version       = var.kubernetes_version
  vpc_id                   = module.network.vpc_id
  node_subnet_ids          = module.network.private_subnet_ids
  control_plane_subnet_ids = module.network.intra_subnet_ids
  public_access_cidrs      = var.api_public_access_cidrs
  access_entries           = merge(local.cluster_admin_entries, local.cluster_viewer_entries)
  node_groups              = var.node_groups
  log_kms_key_arn          = aws_kms_key.logs.arn
  log_retention_days       = var.log_retention_days
  deletion_protection      = var.deletion_protection
  tags                     = local.tags
}

module "eks_cni" {
  source = "../../modules/aws/eks-cni"

  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  vpc_cidr         = module.network.vpc_cidr
  cilium_version   = var.cilium_version
  tags             = local.tags
}

# ---------------------------------------------------------------------------
# Workload identity (EKS Pod Identity)
# ---------------------------------------------------------------------------
module "workload_identity" {
  source = "../../modules/aws/workload-identity"

  cluster_name = module.eks.cluster_name

  identities = merge(
    {
      external-secrets = {
        namespace       = "external-secrets"
        service_account = "external-secrets"
        aws_presets = {
          # Only secrets under "<cluster-name>/" are readable.
          external_secrets_secret_arns = [
            "arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:${local.name}/*",
          ]
        }
      }

      aws-load-balancer-controller = {
        namespace       = "kube-system"
        service_account = "aws-load-balancer-controller"
        aws_presets     = { lb_controller = true }
      }

      # Kyverno pulls signatures/attestations from private ECR to verify images.
      kyverno-admission = {
        namespace       = "kyverno"
        service_account = "kyverno-admission-controller"
        policy_arns     = ["arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"]
      }
    },
    {
      # Falco alerts -> the same SNS topic GuardDuty findings use.
      falcosidekick = {
        namespace       = "falco"
        service_account = "falco-falcosidekick"
        policy_statements = [
          {
            sid       = "PublishAlerts"
            actions   = ["sns:Publish"]
            resources = [module.detection.security_alerts_topic_arn]
          },
          {
            sid       = "EncryptAlerts"
            actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
            resources = [module.detection.security_alerts_kms_key_arn]
          },
        ]
      }
    },
    var.route53_zone_id == null ? {} : {
      cert-manager = {
        namespace       = "cert-manager"
        service_account = "cert-manager"
        aws_presets = {
          cert_manager_hosted_zone_arns = ["arn:${local.partition}:route53:::hostedzone/${var.route53_zone_id}"]
        }
      }
    },
  )

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Supply chain: private registry + CI push identity
# ---------------------------------------------------------------------------
module "registry" {
  source = "../../modules/aws/registry"

  name_prefix              = var.project
  repositories             = var.ecr_repositories
  github_oidc_provider_arn = var.github_oidc_provider_arn
  github_repository        = var.github_repository
  tags                     = local.tags
}

# ---------------------------------------------------------------------------
# Runtime detection & logging (AWS side)
# ---------------------------------------------------------------------------
module "detection" {
  source = "../../modules/aws/detection"

  cluster_name                   = module.eks.cluster_name
  create_guardduty_detector      = var.create_guardduty_detector
  existing_guardduty_detector_id = var.existing_guardduty_detector_id
  alert_emails                   = var.security_alert_emails
  tags                           = local.tags

  # Add-ons need the pod network.
  depends_on = [module.eks_cni]
}

# ---------------------------------------------------------------------------
# GitOps hand-off
# ---------------------------------------------------------------------------
module "platform" {
  source = "../../modules/platform-bootstrap"

  repo_url        = "https://github.com/${var.github_repository}.git"
  target_revision = var.gitops_target_revision

  cluster_values = {
    cloud       = "eks"
    clusterName = module.eks.cluster_name
    region      = var.region
    accountId   = local.account_id
    vpcId       = module.network.vpc_id

    registry = {
      host   = module.registry.registry_host
      prefix = var.project
    }

    # Images in our registry must be signed by this repo's image workflow.
    signer = {
      issuer        = "https://token.actions.githubusercontent.com"
      subjectRegExp = "^https://github\\.com/${replace(var.github_repository, ".", "\\.")}/\\.github/workflows/image\\.yml@refs/heads/main$"
    }

    dns = {
      domain       = var.domain
      route53Zone  = var.route53_zone_id
      acmeEmail    = var.acme_email
      acmeStaging  = var.acme_use_staging
      secretPrefix = "${local.name}/"
    }

    alerts = {
      snsTopicArn = module.detection.security_alerts_topic_arn
    }
  }

  depends_on = [module.eks_cni, module.workload_identity]
}
