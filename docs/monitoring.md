# Monitoring (Prometheus, Alertmanager, Grafana)

Metrics and alerting use **kube-prometheus-stack** (Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter), deployed by Argo CD. Besides standard cluster health, it scrapes the platform's security components and alerts on security signals. So "is a control working?" becomes something you can see and get alerted on.

## What gets deployed

| Piece | Where | Notes |
|---|---|---|
| Prometheus Operator CRDs | Argo CD app `prometheus-operator-crds`, **wave -1** | Installed first so every chart after it can ship its own ServiceMonitor |
| kube-prometheus-stack 92.10.1 (operator v0.94.1) | Argo CD app `kube-prometheus-stack`, wave 2, namespace `monitoring` | `crds.enabled: false`, because the CRDs come from the wave -1 app |
| Encrypted default StorageClass `gp3-encrypted` | `platform/bootstrap/templates/monitoring.yaml` | EBS gp3, encrypted with a customer-managed KMS key |
| EBS CSI driver | Terraform `modules/aws/storage` | EKS add-on, credentials via Pod Identity |
| Platform-alerts SNS topic + Alertmanager role | Terraform `modules/aws/monitoring` | Kept separate from the security-alerts topic |
| Grafana admin secret | ESO `Password` generator → `monitoring/grafana-admin` | Generated in-cluster, once. Never in Git or Terraform state |
| Scrape configs for Terraform-installed components | `monitoring.yaml`: PodMonitors (Cilium agent, Hubble, operator), ServiceMonitor (Argo CD) | Cilium and Argo CD are installed before the CRDs exist |
| Security alert rules | `monitoring.yaml`: PrometheusRule `platform-security` | See below |

Defaults:
- Prometheus: 1 replica, 15-day retention, 40 GB size cap, 50 Gi volume
- Alertmanager: 1 replica, 5 Gi volume

Change retention and volume size through `monitoring.retention` / `monitoring.storageSize` in `platform/bootstrap/values.yaml`. Change resources and other settings in `platform/values/kube-prometheus-stack/common.yaml`.

## Logging and monitoring switches

Every logging and monitoring feature is on by default. Each can be switched off in `terraform/envs/dev/terraform.tfvars`, for example to keep a throwaway dev cluster cheap:

| Variable | Default | Turns on / off | ≈ dev cost when on | Security impact when off |
|---|---|---|---|---|
| `enable_monitoring` | `true` | Prometheus, Alertmanager, Grafana; the Prometheus Operator CRDs; **every chart's ServiceMonitor and dashboard**; the security alert rules; the EBS CSI driver, KMS key and `gp3-encrypted` StorageClass; the platform-alerts SNS topic and Alertmanager role | ~$0.15/day storage plus ~1.5 vCPU / 3 GiB on the nodes | No metrics, dashboards or alert rules. Falco and GuardDuty still alert through the security SNS topic |
| `enable_container_logs` | `true` | CloudWatch Observability add-on (container logs + Container Insights) | ~$0.5–2/day | No central container logs. Falco events are still delivered to SNS |
| `enable_flow_logs` | `true` | VPC flow logs to CloudWatch (KMS) | ~$0.05–0.5/day | No network forensics (CIS AWS 3.9) |
| `control_plane_log_types` | all five | EKS `api`, `audit`, `authenticator`, `controllerManager`, `scheduler` logs; `[]` = off | ~$0.5–2/day, mostly `api` and `audit` | **Keep `audit` + `authenticator`**: they record who did what in the cluster. GuardDuty reads the audit stream separately, but your own investigations need these logs |
| `log_retention_days` | `365` | Retention for flow and control-plane logs | storage only | — |

Lean dev profile (saves roughly $1–3/day against everything on):

```hcl
enable_monitoring       = true                        # or false to free most of a node
enable_container_logs   = false
enable_flow_logs        = true
control_plane_log_types = ["audit", "authenticator"]
log_retention_days      = 30
```

How `enable_monitoring` works end to end:
- **Terraform** skips the `storage` and `monitoring` modules (`count = 0`) and passes `monitoring.enabled` to the root chart.
- **The root chart** (`platform/bootstrap`) then:
  - leaves out the `prometheus-operator-crds` and `kube-prometheus-stack` apps and `templates/monitoring.yaml`
  - stops injecting ServiceMonitor/dashboard values into cert-manager, External Secrets, Kyverno and Falco. Those charts would fail to sync if they asked for ServiceMonitors without the CRDs.

The toggle is covered by tests (see below).

### Tests

- `terraform -chdir=terraform/envs/dev test` runs `tests/logging_monitoring.tftest.hcl`. The providers are mocked, so it needs no AWS credentials. It covers four cases:
  - **defaults:** everything is created
  - **lean dev profile:** monitoring modules are skipped and outputs are null
  - **`control_plane_log_types = []`:** control-plane logging is off
  - **an unknown log type:** rejected by validation
- `scripts/validate-manifests.sh` renders the platform with monitoring both on and off. It then checks:
  - the monitoring apps, CRD-backed resources and namespace appear only when it's on
  - no chart enables metrics when it's off
  - Falco keeps its SNS alert routing either way

Both run in CI (`terraform.yml`, `manifests.yml`) and through `make check`.

## What is scraped

| Source | How | Dashboards |
|---|---|---|
| Kubernetes (kubelet, cAdvisor, API server, CoreDNS, kube-state-metrics, node-exporter) | kube-prometheus-stack defaults | kube-prometheus-stack defaults |
| Cilium agent + Hubble (DNS, drops, TCP, flows, HTTP, policy verdicts) | PodMonitor `cilium-agent` | Cilium chart (`dashboards.enabled`, `hubble.metrics.dashboards.enabled`) |
| Cilium operator | PodMonitor `cilium-operator` | Cilium chart |
| Falco (rule matches by priority, drops, resource use) | Falco chart ServiceMonitor | Falco chart (`grafana.dashboards.enabled`) |
| Kyverno (admission requests, policy results, latency) | Kyverno chart ServiceMonitors | Kyverno chart (`grafana.enabled`) |
| cert-manager (certificate expiry and readiness) | cert-manager chart ServiceMonitor | — |
| External Secrets (sync status, errors) | ESO chart ServiceMonitor | — |
| Argo CD (app sync and health) | ServiceMonitor `argocd` on Services labelled `platform.monitoring/scrape=argocd` | — |
| Tenant workloads | Opt in: label pods `platform.security/metrics: "true"` and add a ServiceMonitor/PodMonitor | — |

Prometheus selects **every** ServiceMonitor, PodMonitor and PrometheusRule in the cluster (`*SelectorNilUsesHelmValues: false`). Charts and teams don't need a special label.

Tenant namespaces are default-deny. Kyverno now also generates an `allow-prometheus-scrape` NetworkPolicy in every tenant namespace. It admits only Prometheus pods from `monitoring`, and only to pods labelled `platform.security/metrics: "true"`.

## Security alert rules (`platform-security`)

| Alert | Pillar | Fires when |
|---|---|---|
| `FalcoHighPriorityEvent` | Runtime detection | Any Falco rule at priority Error or higher matched in the last 5 min |
| `SecurityAgentDown` | Runtime detection | A Falco or Kyverno target has been down for 10 min |
| `KyvernoPolicyDenials` | Workload isolation | A ValidatingPolicy rejected a request in the last 15 min |
| `UnsignedImageRejected` | Supply chain | An ImageValidatingPolicy failed or errored in the last 15 min |
| `NetworkPolicyDropsHigh` | Network segmentation | More than 5 policy-denied drops per second for 15 min |
| `ExternalSecretSyncFailing` | Workload identity | An ExternalSecret has not been Ready for 15 min |
| `CertificateExpiringSoon` | Network segmentation | A certificate expires in under 14 days |
| `ArgoAppDegradedOrOutOfSync` | Platform | An Argo CD app has been Degraded or OutOfSync for 30 min (security controls it deploys may not be in effect) |

These sit alongside kube-prometheus-stack's standard rules for nodes, workloads, storage, the API server and Prometheus itself.

## Alert routing

```
Prometheus rules ──► Alertmanager ──► SNS  <cluster>-platform-alerts ──► email (platform_alert_emails)
GuardDuty, Falco ─────────────────► SNS  <cluster>-security-alerts ──► email (security_alert_emails)
```

- Alertmanager publishes to SNS with SigV4 and its EKS Pod Identity role (`<cluster>-alertmanager`, `sns:Publish` on one topic only). No access keys.
- The two topics are kept separate on purpose: operational noise shouldn't bury security findings. Falco events still reach the security topic directly through Falcosidekick. The Falco *alerts* in Prometheus are for trends and dashboards.
- To route to Slack or PagerDuty instead, subscribe that integration to the SNS topic (AWS Chatbot, or an HTTPS endpoint). Alternatively, add a receiver in `platform/bootstrap/templates/_helpers.tpl` (`platform.kpsInline`).

## Access

Nothing in the stack is exposed publicly.

```bash
# Grafana
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
# then http://localhost:3000, user "admin"

# Prometheus and Alertmanager UIs
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093
```

The Grafana admin password is break-glass only. Hardening that's applied:
- anonymous access and sign-up are off
- secure, SameSite=strict cookies
- no embedding, Gravatar, external snapshots or update checks
- no persistent volume: dashboards and datasources come from Git and ConfigMaps

Next step: SSO through `grafana.ini` `auth.generic_oauth` (or Identity Center SAML).

## Cost

Rough monthly add-on, in dev:
- **~$5–6:** 55 Gi of gp3 storage
- **CPU and memory:** about 1.5 vCPU and 3 GiB requested, which fits on the existing two `m7i.large` nodes for dev

## Known limits

- **Single replicas:** Prometheus and Alertmanager each run one replica. For production, set `replicas: 2` and add Thanos or Amazon Managed Service for Prometheus via `remoteWrite`.
- **Control-plane metrics:** etcd, scheduler and controller-manager metrics aren't scraped, because EKS manages them. API server metrics are scraped.
- **Hubble flow logs:** still not exported or retained, only metrics (see Known gap 16 in [security-controls.md](security-controls.md#known-gaps)).
- **Alertmanager → SNS:** relies on Alertmanager's SigV4 client picking up EKS Pod Identity credentials. Verify on first deploy with a test alert:
  ```bash
  kubectl -n monitoring exec sts/alertmanager-kube-prometheus-stack-alertmanager -- \
    amtool alert add test severity=warning --alertmanager.url=http://localhost:9093
  ```
