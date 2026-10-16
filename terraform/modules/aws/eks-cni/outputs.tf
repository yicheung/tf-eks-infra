output "ready" {
  description = "Depend on this to run after the pod network (Cilium + CoreDNS) is up."
  value       = aws_eks_addon.coredns.id
}

output "cilium_version" {
  description = "Installed Cilium chart version."
  value       = helm_release.cilium.version
}
