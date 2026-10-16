output "argocd_namespace" {
  description = "Namespace Argo CD runs in."
  value       = helm_release.argocd.namespace
}

output "argocd_ui_command" {
  description = "How to reach the Argo CD UI (no public exposure by default)."
  value       = "kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443"
}
