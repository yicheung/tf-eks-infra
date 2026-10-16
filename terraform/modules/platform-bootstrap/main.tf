# Cloud-neutral hand-off from Terraform to GitOps.
#
# Terraform installs exactly two things in the cluster:
#   1. Argo CD (hardened values)
#   2. The AppProjects and one root Application that points at platform/bootstrap
#
# Everything else (cert-manager, ESO, Kyverno, Falco, policies, workloads) is
# declared in Git and reconciled by Argo CD. The `cluster_values` map is the
# only cloud-specific input: it's passed to the root chart, which uses
# `cloud: eks|gke` to pick value files and cloud-only components.

resource "helm_release" "argocd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    global = {
      networkPolicy = { create = true }
    }

    configs = {
      params = {
        # TLS stays on; reach the UI with port-forward or an internal Gateway.
        "server.insecure" = false
      }
      cm = {
        # Turn admin off once SSO (configs.cm.oidc.config) is set up.
        "admin.enabled"           = var.argocd_admin_enabled
        "exec.enabled"            = false
        "users.anonymous.enabled" = false
        "statusbadge.enabled"     = false
        "timeout.reconciliation"  = "180s"
      }
      rbac = {
        # Authenticated users get nothing unless a role grants it.
        "policy.default" = ""
        "policy.csv"     = var.argocd_rbac_policy_csv
      }
    }

    dex = { enabled = false }

    server = {
      service = { type = "ClusterIP" }
    }

    notifications = { enabled = false }
  })]
}

resource "helm_release" "argocd_root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = "argocd"

  values = [yamlencode({
    projects = {
      # Platform components: may create cluster-scoped resources.
      platform = {
        namespace   = "argocd"
        description = "Cluster platform: CNI add-ons, security controllers, policies"
        sourceRepos = concat([var.repo_url], var.platform_chart_repos)
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = "*"
        }]
        clusterResourceWhitelist = [{ group = "*", kind = "*" }]
      }

      # Application teams: own namespaces only, nothing cluster-scoped except
      # their Namespace object, and no RBAC or policy objects.
      workloads = {
        namespace   = "argocd"
        description = "Application workloads"
        sourceRepos = [var.repo_url]
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = "app-*"
        }]
        clusterResourceWhitelist = [{ group = "", kind = "Namespace" }]
        namespaceResourceBlacklist = [
          { group = "rbac.authorization.k8s.io", kind = "Role" },
          { group = "rbac.authorization.k8s.io", kind = "RoleBinding" },
          { group = "", kind = "ResourceQuota" },
          { group = "", kind = "LimitRange" },
          { group = "policies.kyverno.io", kind = "*" },
        ]
      }
    }

    applications = {
      root = {
        namespace = "argocd"
        project   = "platform"
        finalizers = [
          "resources-finalizer.argocd.argoproj.io",
        ]
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = "platform/bootstrap"
          helm = {
            valuesObject = merge(var.cluster_values, {
              repoURL        = var.repo_url
              targetRevision = var.target_revision
            })
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
