# Security controls

Each control is listed with the file that enforces it and the guidance it maps to.

**Abbreviations:**
- **CIS**: CIS Amazon EKS Benchmark
- **NSA**: NSA/CISA Kubernetes Hardening Guide
- **800-190**: NIST SP 800-190, Application Container Security Guide

## Coverage summary

Status of the five pillars. All controls are implemented in code and have passed static validation (`terraform validate`, tflint, Checkov, Trivy, kubeconform, Kyverno CLI). **They have not yet been verified on a live cluster.** Items marked *(new)* were found in the 2026-10-16 coverage review.

| Pillar | Status | In place | Still open |
|---|---|---|---|
| **Workload identity** | ✅ Covered | One IAM role per ServiceAccount via EKS Pod Identity, no static keys. IMDSv2 hop limit 1, so pods can't use the node role. No token automount. EKS access entries. CI uses GitHub OIDC. | CI apply role still has AdministratorAccess. Argo CD SSO not configured. |
| **Supply chain & image hardening** | ✅ Covered | ECR: immutable tags, KMS, continuous scanning. CI: Trivy gate, SBOM, keyless cosign, SLSA provenance. Kyverno admits only signed, digest-pinned images from our registry. | Base images not digest-pinned. Kyverno vs cosign v3 signature format untested. *(new)* Platform component images (Falco, Kyverno, ESO, …) skip signature and digest checks because their namespaces are exempt. |
| **Workload isolation** | ✅ Covered (tenant namespaces) | PSA `restricted`, read-only root FS, resource limits, dedicated SAs, no host namespaces. Bottlerocket nodes. KMS-encrypted Secrets. Argo CD AppProjects fence tenants. | *(new)* Tenant and platform pods share one node group (no taints or separate pools). *(new)* No per-namespace ResourceQuota/LimitRange. *(new)* No Kubernetes RBAC model for tenant teams. No sandboxed runtime (gVisor/Kata). |
| **Network segmentation** | ✅ Covered | Private subnets, no node public IPs, restricted API endpoint, VPC endpoints, flow logs. Cilium with WireGuard. Generated default-deny per tenant namespace. Single shared Gateway with TLS; no tenant LoadBalancer/NodePort Services. | *(new)* Tenants can create an allow-all NetworkPolicy that undoes default-deny. *(new)* No FQDN egress allow-listing: allowed egress can reach any internet host. No WAF. No workload-authenticated mTLS (WireGuard encrypts node-to-node only). |
| **Runtime detection & logging** | ✅ Covered | Control-plane and audit logs (KMS, 365 days). GuardDuty EKS audit + Runtime Monitoring. Falco → Falcosidekick → SNS, shared with GuardDuty findings. Container logs to CloudWatch. Hubble metrics. Prometheus/Alertmanager/Grafana scrape Falco, Kyverno, Cilium/Hubble, cert-manager, ESO and Argo CD, with security alert rules routed to SNS. | Hubble flow logs not exported or retained. Prometheus and Alertmanager run single replicas, with no long-term storage. CloudTrail / Security Hub are org-level and out of scope. |

Monitoring (Prometheus, Alertmanager, Grafana) was added afterwards; see [monitoring.md](monitoring.md).

**Recommended next fixes, in priority order** (all doable before the first apply):

1. Block allow-all NetworkPolicies from tenants (Kyverno ValidatingPolicy).
2. FQDN egress allow-lists with CiliumNetworkPolicy `toFQDNs`.
3. Pin platform component images by digest, and verify signatures where upstream signs them.
4. Generate a ResourceQuota and LimitRange with each tenant namespace, alongside default-deny.
5. Split nodes into `platform` and `workloads` node groups with taints and nodeSelectors.

## 1. Workload identity

| Control | Where | Maps to |
|---|---|---|
| One IAM role per Kubernetes ServiceAccount via **EKS Pod Identity**; no IRSA OIDC provider, no static keys | `terraform/modules/aws/workload-identity`, `envs/dev/main.tf` (`identities`) | CIS 5.2.x (dedicated, least-privilege service identities); NSA "Authentication" |
| ESO can read only `secretsmanager:secret:<cluster>/*`; the ClusterSecretStore serves only namespaces labelled `platform.security/tenant=true` | `envs/dev/main.tf`, `platform/bootstrap/templates/cluster-config.yaml` | 800-190 §4.1.4 (secrets) |
| Nodes enforce **IMDSv2, hop limit 1**, so pods can't borrow the node role | `modules/aws/eks/main.tf` (`metadata_options`) | CIS 5.4.x (restrict access to instance metadata) |
| ServiceAccount tokens aren't mounted unless needed; Pods may not use `default` SA | `workloads/sample/base/deployment.yaml`, `policies/kyverno/templates/workload-isolation.yaml` | CIS 4.1.5 / 4.1.6 |
| Cluster access through **EKS access entries** (API mode); no aws-auth ConfigMap, no implicit creator-admin | `modules/aws/eks/main.tf`, `envs/dev/main.tf` | CIS 5.5.1 (manage users with IAM) |
| CI → AWS with **GitHub OIDC**; plan role read-only, apply role bound to a protected GitHub Environment, push role bound to `main` | `terraform/bootstrap/github-oidc.tf`, `modules/aws/registry` | SLSA Build L2/L3 (hosted, isolated builder) |

## 2. Supply chain & image hardening

| Control | Where | Maps to |
|---|---|---|
| Private ECR: **immutable tags**, KMS encryption, lifecycle cleanup | `modules/aws/registry` | CIS 5.1.x (image registry) |
| **Continuous** registry scanning (Amazon Inspector enhanced) | `modules/aws/registry` (`aws_ecr_registry_scanning_configuration`) | CIS 5.1.1; 800-190 §4.1.1 |
| CI fails on fixable HIGH/CRITICAL CVEs (Trivy) before pushing | `.github/workflows/image.yml` | 800-190 §4.1.1 |
| **SBOM** (SPDX) generated and attached as a signed attestation | `.github/workflows/image.yml` | EO 14028 / NTIA minimum elements |
| **Keyless cosign signature** (GitHub OIDC identity, Rekor transparency log) | `.github/workflows/image.yml` | SLSA; 800-190 §4.1.5 (image trust) |
| **SLSA build provenance** pushed to the registry | `.github/workflows/image.yml` (`attest-build-provenance`) | SLSA Build L2+ |
| Admission: images must come from `<registry>/<prefix>/`, **pinned by digest**, and **signed by this repo's `image.yml` on `main`** | `policies/kyverno/templates/supply-chain.yaml` | 800-190 §4.1.5; NSA "Image scanning / signing" |
| Distroless, non-root, static base image | `app/sample/Dockerfile` | 800-190 §4.1.2 |
| All GitHub Actions pinned by commit SHA; Dependabot keeps pins and base images fresh | `.github/workflows/*`, `.github/dependabot.yml` | OpenSSF Scorecard "Pinned-Dependencies" |
| IaC scanned on every PR: `terraform validate`, tflint, Trivy config, Checkov | `.github/workflows/terraform.yml`, `.checkov.yaml` | Shift-left |

## 3. Workload isolation

| Control | Where | Maps to |
|---|---|---|
| **Pod Security Admission `restricted`** (enforce/audit/warn) on tenant namespaces; a policy rejects tenant namespaces without it | `workloads/sample/base/namespace.yaml`, `policies/kyverno/templates/workload-isolation.yaml` | CIS 4.2.x; NSA "Pod security" |
| Read-only root FS, CPU/memory requests, memory limit, no host namespaces | `policies/kyverno/templates/workload-isolation.yaml` | CIS 4.2.x, 4.6.x; 800-190 §4.4 |
| **Bottlerocket** nodes (minimal, immutable OS, SELinux enforcing), encrypted volumes, no SSH | `modules/aws/eks/main.tf` | CIS 3.x (node config); 800-190 §4.5 |
| **Argo CD AppProjects**: `workloads` may deploy only to `app-*` namespaces and can't create RBAC, quotas or policies; the built-in `default` project is emptied | `modules/platform-bootstrap/main.tf`, `platform/bootstrap/templates/cluster-config.yaml` | NSA "Least privilege" |
| Kubernetes Secrets envelope-encrypted with a customer-managed KMS key | `modules/aws/eks/main.tf` (`encryption_config`) | CIS 5.3.1 |
| Platform components with elevated needs (Falco, CNI) are confined to named system namespaces, exempt by explicit list | `platform/bootstrap/values.yaml` (`systemNamespaces`) | — |

## 4. Network segmentation & security

| Control | Where | Maps to |
|---|---|---|
| Nodes and pods in **private subnets**, no public IPs; control-plane ENIs in isolated subnets; default SG has no rules | `modules/aws/network` | CIS 5.4.3 (private nodes); CIS AWS 5.4 |
| API endpoint **private**; public access only from listed CIDRs (0.0.0.0/0 rejected by validation) | `modules/aws/eks` (`public_access_cidrs`) | CIS 5.4.2 |
| **VPC endpoints** for ECR, STS, EKS Auth, logs, EC2, KMS, Secrets Manager, S3 | `modules/aws/network` | Defense in depth |
| **VPC flow logs** (KMS, 365 days) | `modules/aws/network` | CIS AWS 3.9 |
| **Cilium** replaces kube-proxy + VPC CNI: eBPF datapath, identity-aware policy | `modules/aws/eks-cni` | NSA "Network separation" |
| **WireGuard** pod-to-pod encryption between nodes | `modules/aws/eks-cni` (`encryption`) | NSA "Encrypt traffic" |
| **Default-deny ingress + egress** generated for every tenant namespace (plus DNS egress) | `policies/kyverno/templates/network.yaml` | CIS 5.3.2; NSA "Network policies" |
| Workloads allow only Gateway → app:8080 and DNS | `workloads/sample/base/networkpolicy.yaml`, `overlays/eks/cilium-gateway-ingress.yaml` | — |
| One **shared Gateway** (NLB → Cilium) is the only way in; tenants can't create LoadBalancer/NodePort Services or externalIPs | `platform/bootstrap/templates/gateway.yaml`, `policies/kyverno/templates/network.yaml` | NSA "Limit exposure" |
| **TLS** at the Gateway with a cert-manager wildcard cert (DNS-01, Route 53); HTTP redirects to HTTPS | `platform/bootstrap/templates/gateway.yaml`, `cluster-config.yaml` | — |

## 5. Runtime detection & logging

| Control | Where | Maps to |
|---|---|---|
| EKS control-plane logs: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler` → CloudWatch (KMS, 365 d) | `modules/aws/eks` | CIS 2.1.1; NSA "Audit logging" |
| **GuardDuty** EKS audit-log analysis + **EKS Runtime Monitoring** (agent auto-managed) | `modules/aws/detection` | 800-190 §4.4.4 |
| **Falco** (modern eBPF), upstream rules + a platform rule; **Falcosidekick** routes alerts | `platform/values/falco/` | 800-190 §4.4.4 |
| GuardDuty findings ≥ 7 and Falco `error`+ go to **one SNS topic** (KMS) | `modules/aws/detection`, `platform/bootstrap/templates/apps.yaml` | Incident response |
| **Hubble** flow, DNS, drop and policy-verdict metrics | `modules/aws/eks-cni` | NSA "Monitoring" |
| **Prometheus + Alertmanager + Grafana** (kube-prometheus-stack) scraping every security component; volumes on KMS-encrypted gp3 | `platform/values/kube-prometheus-stack/`, `modules/aws/storage` | NSA "Monitoring"; 800-190 §4.4.4 |
| **Security alert rules**: Falco high-priority events, agent down, Kyverno denials, image-verification failures, policy-drop spikes, ESO sync failures, cert expiry, Argo CD drift → Alertmanager → SNS (Pod Identity) | `platform/bootstrap/templates/monitoring.yaml`, `modules/aws/monitoring` | Incident response |
| Grafana: no public exposure, in-cluster generated admin secret, anonymous/sign-up off, secure cookies | `platform/values/kube-prometheus-stack/common.yaml` | CIS 5.x (least exposure) |
| Container logs + Container Insights via the CloudWatch Observability add-on (Pod Identity) | `modules/aws/detection` | — |
| Kyverno policy reports (background scans) for audit evidence | Kyverno defaults | — |

## Known gaps

These are deliberate next steps, not oversights:

1. **Apply role uses `AdministratorAccess`** (`terraform/bootstrap`). Replace it with a scoped policy plus a permissions boundary. This is the one Checkov skip that's a real gap (`CKV_AWS_274`).
2. **Terraform needs to reach the cluster API** for the Helm releases. With the API private-only, run CI from a self-hosted runner in the VPC (or allow-list a static egress IP). GitHub-hosted runners have dynamic IPs.
3. **Cosign v3 signature format vs. Kyverno.** Confirm `kyverno` verifies the cosign v3 bundle/referrer format in your setup before relying on `Deny`. If it doesn't, sign with `--new-bundle-format=false` or temporarily set `validationActions: [Audit]`.
4. **Base images aren't digest-pinned yet** in `app/sample/Dockerfile`. Pin them once, and Dependabot will keep them updated.
5. **No WAF.** The NLB passes TLS through to Cilium. For L7 WAF, put AWS WAF on an ALB (AWS LB Controller Gateway API support) or CloudFront in front.
6. **Argo CD SSO** isn't wired up yet. The local admin user stays enabled until `configs.cm.oidc.config` is set.
7. ~~**Metrics stack**~~: **resolved.** kube-prometheus-stack added, see [monitoring.md](monitoring.md). Remaining: single-replica Prometheus/Alertmanager, no long-term storage (Thanos or Amazon Managed Prometheus), and Grafana SSO.
8. **Org-level controls** (GuardDuty delegated admin, Security Hub, CloudTrail org trail, SCPs) belong in an AWS Organizations repo.
9. **Tenant NetworkPolicy guardrail.** Nothing stops a tenant from adding an allow-all NetworkPolicy that cancels default-deny. Add a Kyverno policy that rejects empty-selector or `0.0.0.0/0` ingress and egress rules in tenant namespaces.
10. **Egress allow-listing.** Default-deny blocks egress, but any egress a tenant does allow can reach any host. Use CiliumNetworkPolicy `toFQDNs` (with DNS proxy) to name allowed external hosts.
11. **Platform images aren't verified.** System namespaces are exempt from the registry, digest and signature policies. Pin chart images by digest, and add a separate ImageValidatingPolicy for upstream images that are signed (e.g. Kyverno, cert-manager, Cilium).
12. **No per-namespace quotas.** Generate a ResourceQuota and LimitRange with each tenant namespace, alongside the default-deny NetworkPolicies.
13. **Shared nodes.** Platform and tenant pods run on one node group. Split into `platform` and `workloads` node groups with taints and nodeSelectors, so a compromised tenant pod can't land next to Argo CD or Kyverno.
14. **Tenant RBAC.** Team access is only fenced through Argo CD AppProjects. Define Kubernetes Roles/RoleBindings (or EKS access-entry namespace scopes) for direct `kubectl` access.
15. **No runtime sandbox** (gVisor/Kata) for untrusted workloads.
16. **Hubble flow logs** aren't exported or retained (metrics only). Enable the Hubble exporter and ship flows to CloudWatch or S3.
