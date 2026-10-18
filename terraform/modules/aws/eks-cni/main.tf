# Pod networking for EKS: Gateway API CRDs -> Cilium (ENI mode, kube-proxy
# replacement, WireGuard, Hubble, Gateway API) -> CoreDNS.
#
# Order matters:
#   1. Gateway API CRDs must exist before the Cilium operator starts, or its
#      Gateway controller stays disabled.
#   2. Cilium must be running before CoreDNS, which needs a pod network.
#
# On GKE this module is replaced by Dataplane V2 (managed Cilium) plus the
# managed Gateway API CRDs, so nothing here is cloud-neutral on purpose.

locals {
  k8s_service_host = trimprefix(var.cluster_endpoint, "https://")
}

# ---------------------------------------------------------------------------
# 1. Gateway API CRDs (vendored, pinned; see charts/gateway-api-crds)
# ---------------------------------------------------------------------------
resource "helm_release" "gateway_api_crds" {
  name      = "gateway-api-crds"
  chart     = "${path.module}/charts/gateway-api-crds"
  namespace = "kube-system"
}

# ---------------------------------------------------------------------------
# 2. Cilium operator identity (ENI IPAM needs EC2 ENI permissions)
# ---------------------------------------------------------------------------
module "cilium_operator_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.9"

  name            = "${var.cluster_name}-cilium-operator"
  use_name_prefix = false
  description     = "Cilium operator: ENI and IP prefix management"

  attach_custom_policy = true
  policy_statements = [
    {
      sid = "CiliumEniDescribe"
      actions = [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVpcs",
      ]
      resources = ["*"]
    },
    {
      # Cilium's documented ENI permission set. Tighten further with an
      # ec2:Vpc / aws:ResourceTag condition once validated in your account.
      sid = "CiliumEniManage"
      actions = [
        "ec2:AssignPrivateIpAddresses",
        "ec2:AttachNetworkInterface",
        "ec2:CreateNetworkInterface",
        "ec2:CreateTags",
        "ec2:DeleteNetworkInterface",
        "ec2:DetachNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:UnassignPrivateIpAddresses",
      ]
      resources = ["*"]
    },
  ]

  associations = {
    operator = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "cilium-operator"
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 3. Cilium
# ---------------------------------------------------------------------------
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"
  wait       = true
  timeout    = 900

  values = [yamlencode({
    # --- Datapath -----------------------------------------------------------
    kubeProxyReplacement = true
    k8sServiceHost       = local.k8s_service_host
    k8sServicePort       = 443

    # ENI mode: pods get VPC-routable IPs, so the EKS control plane can reach
    # admission webhooks (Kyverno, cert-manager, ESO) without hostNetwork.
    eni = {
      enabled                   = true
      awsEnablePrefixDelegation = true
    }
    ipam                  = { mode = "eni" }
    routingMode           = "native"
    ipv4NativeRoutingCIDR = var.vpc_cidr
    bpf                   = { masquerade = true }

    # --- Transparent encryption between nodes (pod-to-pod) --------------------
    encryption = {
      enabled        = true
      type           = "wireguard"
      nodeEncryption = false
    }

    # --- Policy -----------------------------------------------------------------
    # "default": pods are open until a policy selects them. Namespaces are given
    # a default-deny NetworkPolicy by Kyverno (policies/kyverno), which is what
    # makes the cluster deny-by-default without breaking system components.
    policyEnforcementMode = "default"

    # --- Gateway API (north-south ingress) ------------------------------------------
    gatewayAPI = {
      enabled = true
    }

    # --- Flow observability -----------------------------------------------------------
    # Agent and operator metrics (scraped with PodMonitors from GitOps) and
    # Grafana dashboards as ConfigMaps in kube-system (the Grafana sidecar
    # watches all namespaces; "monitoring" does not exist yet at this point).
    prometheus = { enabled = true }
    dashboards = { enabled = true }

    hubble = {
      enabled = true
      relay   = { enabled = true }
      metrics = {
        dashboards = { enabled = true }
        enabled = [
          "dns",
          "drop",
          "tcp",
          "flow",
          "port-distribution",
          "icmp",
          "httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction",
          "policy:sourceContext=app|workload-name|pod|reserved-identity;destinationContext=app|workload-name|pod|dns|reserved-identity;labelsContext=source_namespace,destination_namespace",
        ]
      }
    }

    operator = {
      replicas   = 2
      prometheus = { enabled = true }
      dashboards = { enabled = true }
    }

    # Required for the operator to pick up its Pod Identity credentials.
    serviceAccounts = {
      operator = { name = "cilium-operator" }
    }
  })]

  depends_on = [
    helm_release.gateway_api_crds,
    module.cilium_operator_identity,
  ]
}

# ---------------------------------------------------------------------------
# 4. Add-ons that need a pod network
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [helm_release.cilium]
}
