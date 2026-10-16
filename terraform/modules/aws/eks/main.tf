# EKS control plane and managed node groups, hardened.
#
# Controls implemented here:
#   - API endpoint: private always; public only if allow-listed CIDRs are given
#   - Secrets envelope encryption with a customer-managed KMS key
#   - All control-plane log types to CloudWatch (KMS-encrypted, retained)
#   - Access entries (API auth mode) instead of aws-auth; no implicit creator admin
#   - Bottlerocket nodes, IMDSv2 required with hop limit 1, encrypted volumes
#   - No self-managed add-ons: no aws-node or kube-proxy. Cilium replaces both
#     and is installed by the eks-cni module.
#   - EKS Pod Identity agent for workload identity

locals {
  node_taints = {
    # Keep application pods off a node until the Cilium agent is ready there.
    # Cilium removes this taint itself.
    cilium = {
      key    = "node.cilium.io/agent-not-ready"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.node_subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  # --- API endpoint exposure ---------------------------------------------------
  endpoint_private_access      = true
  endpoint_public_access       = length(var.public_access_cidrs) > 0
  endpoint_public_access_cidrs = var.public_access_cidrs

  # --- Authentication / authorization -------------------------------------------
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries                           = var.access_entries

  # --- Secrets encryption -------------------------------------------------------
  create_kms_key                  = true
  kms_key_description             = "${var.cluster_name} Kubernetes secrets envelope encryption"
  kms_key_deletion_window_in_days = 30
  enable_kms_key_rotation         = true
  encryption_config = {
    resources = ["secrets"]
  }

  # --- Control-plane logging ----------------------------------------------------
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days
  cloudwatch_log_group_kms_key_id        = var.log_kms_key_arn

  # --- Platform behaviour ---------------------------------------------------------
  deletion_protection = var.deletion_protection
  upgrade_policy = {
    support_type = "STANDARD"
  }

  # IRSA OIDC provider is not needed: workload identity uses EKS Pod Identity.
  enable_irsa = false

  # Add-ons that must exist before nodes join. CoreDNS and the rest are
  # installed by eks-cni after Cilium, because they need a working pod network.
  addons = {
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  # Node SG: the module's recommended rules cover node<->node TCP, control
  # plane -> kubelet and webhook ports. Cilium also needs WireGuard (UDP 51871)
  # and ICMP health probes between nodes.
  node_security_group_enable_recommended_rules = true
  node_security_group_additional_rules = {
    cilium_wireguard = {
      description = "Cilium WireGuard node-to-node"
      protocol    = "udp"
      from_port   = 51871
      to_port     = 51871
      type        = "ingress"
      self        = true
    }
    cilium_health_icmp = {
      description = "Cilium health ICMP node-to-node"
      protocol    = "icmp"
      from_port   = 8
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  eks_managed_node_groups = {
    for name, ng in var.node_groups : name => {
      ami_type       = ng.ami_type
      instance_types = ng.instance_types
      capacity_type  = ng.capacity_type
      min_size       = ng.min_size
      max_size       = ng.max_size
      desired_size   = ng.desired_size
      labels         = ng.labels
      taints         = merge(local.node_taints, ng.taints)

      # IMDSv2 only, hop limit 1: pods cannot reach node credentials.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      # Bottlerocket: xvda = OS, xvdb = container data. Both encrypted.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 4
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            volume_size           = ng.disk_size_gb
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # No SSH. Use SSM Session Manager (Bottlerocket admin container) if you
      # need a shell on a node.
      node_repair_config = {
        enabled = true
      }

      update_config = {
        max_unavailable_percentage = 33
      }
    }
  }

  tags = var.tags
}
