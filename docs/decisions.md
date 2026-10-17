# Design decisions

Short ADRs. Each one records the choice, why it was made, and what it costs.

## 001: Terraform for cloud resources, Argo CD for in-cluster

- **Choice:** Terraform stops at "cluster + CNI + Argo CD + root app". Everything else is GitOps.
- **Why:** The Terraform Helm/Kubernetes providers handle CRD-heavy, frequently updated controllers poorly, and drift goes unnoticed between applies. Argo CD reconciles continuously and shows drift.
- **Cost:** Two tools to learn. Some values (role ARNs, region, topic ARN) cross the boundary through `cluster_values`.

## 002: EKS Pod Identity over IRSA

- **Choice:** Pod Identity associations; `enable_irsa = false`.
- **Why:** No per-cluster OIDC provider or trust-policy edits, no ServiceAccount annotations (so manifests stay cloud-neutral), and session tags for ABAC.
- **Cost:** Requires the `eks-pod-identity-agent` add-on; a few older SDKs don't support it.

## 003: Cilium in ENI mode, replacing VPC CNI and kube-proxy

- **Choice:** No self-managed add-ons. Cilium with `ipam.mode=eni`, prefix delegation, `kubeProxyReplacement=true`, WireGuard, Hubble and Gateway API.
- **Why:**
  - One dataplane for policy, encryption, L7 visibility and ingress.
  - ENI mode keeps pod IPs VPC-routable, so the EKS control plane can call admission webhooks (Kyverno, cert-manager, ESO) without `hostNetwork`.
- **Cost:**
  - Not an AWS-supported CNI, so Cilium upgrades are on us.
  - The Cilium operator needs EC2 ENI permissions (granted through Pod Identity).
  - Gateway API CRDs must be installed first, which is why they're vendored into `eks-cni`.

## 004: Kyverno CEL policies (`policies.kyverno.io/v1`)

- **Choice:** ValidatingPolicy, ImageValidatingPolicy and GeneratingPolicy, not ClusterPolicy.
- **Why:** ClusterPolicy was deprecated in Kyverno 1.17 and is planned for removal around 1.20. CEL policies align with Kubernetes ValidatingAdmissionPolicy.
- **Cost:** Newer API with fewer community examples; image verification with cosign v3 needs testing (see known gaps).

## 005: PSA for the baseline, Kyverno for the rest

- **Choice:** Pod Security Admission `restricted` does the heavy lifting. Kyverno adds only what PSA can't express (read-only root FS, limits, registry/digest, signatures) and makes sure namespaces actually carry the PSA label.
- **Why:** PSA is built in, fast, and can't be uninstalled. Duplicating it in Kyverno adds latency and drift.

## 006: One shared Gateway

- **Choice:** The platform owns `gateway-system/shared`. Tenants attach HTTPRoutes and may not create LoadBalancer/NodePort Services.
- **Why:** One internet-facing entry point to protect, monitor and put TLS on. Teams don't spawn load balancers.
- **Cost:** The Gateway is a shared dependency. Split it per environment or trust zone when needed.

## 007: Bottlerocket nodes

- **Choice:** `BOTTLEROCKET_x86_64` managed node groups, no SSH.
- **Why:** Minimal, immutable, SELinux-enforcing OS with atomic updates. A smaller attack surface than AL2023 for nodes that only run containers.
- **Cost:** No package manager on the host. Debug through the admin container over SSM.

## 008: Self-hosted kube-prometheus-stack, CRDs installed first

- **Choice:** kube-prometheus-stack via Argo CD, with the Prometheus Operator CRDs in a separate app at sync wave -1 and `crds.enabled: false` in the stack.
- **Why:**
  - Every other chart (Kyverno, Falco, cert-manager, ESO) can ship its own ServiceMonitor without ordering hacks.
  - Components installed by Terraform before the CRDs exist (Cilium, Argo CD) get PodMonitors/ServiceMonitors from GitOps instead.
  - Self-hosted keeps the stack cloud-neutral for GKE.
- **Cost:**
  - The CRD chart version must track the operator version in kube-prometheus-stack.
  - Single replicas and local retention: production needs HA plus Thanos or Amazon Managed Service for Prometheus.

## 009: Separate SNS topics for security and operational alerts

- **Choice:** GuardDuty and Falcosidekick publish to `<cluster>-security-alerts`; Alertmanager publishes to `<cluster>-platform-alerts`.
- **Why:** Security findings shouldn't be buried in capacity and availability noise, and the two usually go to different people.
- **Cost:** Two subscriptions to manage (`security_alert_emails`, `platform_alert_emails`).

