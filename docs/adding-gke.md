# Adding GKE

The repo is split so that a second cloud means **new modules plus value overlays**, not a restructure.

## What is already cloud-neutral

| Piece | Why it ports |
|---|---|
| `terraform/modules/platform-bootstrap` | Takes only a kube connection and a `cluster_values` map (`cloud = "gke"`) |
| `platform/bootstrap` (root chart) | Picks `platform/values/<component>/<cloud>.yaml` and branches on `.Values.cloud` |
| `policies/kyverno` | Parameterized by registry host, signer identity and credential provider (`[google]`) |
| `workloads/*/base` | Plain Kubernetes; cloud specifics live in `overlays/<cloud>` |
| CI supply chain | Same Trivy/SBOM/cosign/provenance steps; only the registry login changes |

## The contract each cloud implements

| Concept | EKS module (exists) | GKE module (to add) |
|---|---|---|
| Network | `aws/network`: VPC, private subnets, NAT, endpoints, flow logs | `gcp/network`: VPC, subnet with secondary ranges, Cloud NAT, Private Google Access, flow logs |
| Cluster | `aws/eks`: private endpoint, KMS secrets, access entries, Bottlerocket, IMDSv2 | `gcp/gke`: private nodes, master authorized networks, CMEK `database_encryption`, Shielded Nodes + Secure Boot, COS_CONTAINERD, `workload_metadata_config = GKE_METADATA`, release channel, Binary Authorization |
| CNI | `aws/eks-cni`: Gateway CRDs + Cilium + CoreDNS | **Not needed**: `datapath_provider = ADVANCED_DATAPATH` (Dataplane V2, Cilium-based) + `gateway_api_config { channel = "CHANNEL_STANDARD" }` |
| Identities | `aws/workload-identity`: `identities` map → Pod Identity | `gcp/workload-identity`: **same `identities` map** → IAM bindings on `principal://iam.googleapis.com/projects/N/locations/global/workloadIdentityPools/P.svc.id.goog/subject/ns/NS/sa/SA` (direct WIF, no GSA needed) |
| Registry | `aws/registry`: ECR + OIDC push role | `gcp/registry`: Artifact Registry (immutable tags, CMEK, vulnerability scanning) + Workload Identity Federation for GitHub |
| Detection | `aws/detection`: GuardDuty + SNS + CloudWatch | `gcp/detection`: Security Command Center / GKE threat detection, Pub/Sub topic, Cloud Logging sinks |

## Step by step

1. **Terraform:** add `terraform/modules/gcp/{network,gke,workload-identity,registry,detection}` with the inputs and outputs in the table. Add `terraform/envs/dev-gke` that calls them, then `platform-bootstrap` with:
   ```hcl
   cluster_values = {
     cloud       = "gke"
     clusterName = module.gke.cluster_name
     region      = var.region
     projectId   = var.project_id
     registry    = { host = "${var.region}-docker.pkg.dev", prefix = "${var.project_id}/tf-eks-infra" }
     signer      = { issuer = "https://token.actions.githubusercontent.com", subjectRegExp = "..." }
     dns         = { domain = var.domain, ... }
   }
   ```
2. **Value overlays:** add `platform/values/<component>/gke.yaml` where needed.
   - Falco: `driver.kind: modern_ebpf` works on COS. Falcosidekick switches to `gcp.pubsub`.
   - cert-manager: Cloud DNS solver.
   - Kyverno: none.
3. **Root chart:** in `platform/bootstrap/templates/cluster-config.yaml`, add `else` branches for the GCP ClusterSecretStore (`gcpsm`, ambient Workload Identity) and the Cloud DNS ClusterIssuer. `gateway.yaml` already switches `gatewayClassName` to `gke-l7-global-external-managed`. Skip the AWS LB Controller app (it's EKS-only already).
4. **Policies:** pass `imageCredentialProviders: [google]` from the root chart when `cloud == "gke"`.
5. **Workloads:** add `workloads/sample/overlays/gke`. Replace the `CiliumNetworkPolicy fromEntities: ingress` with a `NetworkPolicy` that allows the GKE Gateway proxy-only subnet and Google health-check ranges (`35.191.0.0/16`, `130.211.0.0/22`). Point the ExternalSecret key at the GCP secret name.
6. **CI:** add a `google-github-actions/auth` (WIF) + Artifact Registry login path in `image.yml`, selected by a matrix or a separate workflow.

No file under `platform/bootstrap/templates/_helpers.tpl`, `policies/`, or `workloads/*/base` needs to change.
