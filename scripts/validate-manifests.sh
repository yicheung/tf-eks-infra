#!/usr/bin/env bash
# Render every Helm chart / kustomization under platform/, policies/ and
# workloads/ with representative values, then validate with kubeconform
# against Kubernetes + CRD schemas. Used by CI and `make manifests`.
set -euo pipefail

HELM_VERSION="${HELM_VERSION:-v4.3.1}"
KUSTOMIZE_VERSION="${KUSTOMIZE_VERSION:-v5.8.3}"
KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-v0.8.0}"
K8S_VERSION="${K8S_VERSION:-1.35.0}"  # newest version in the kubeconform schema set

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/.bin"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"; case "$arch" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; esac

install_tools() {
  if ! command -v helm >/dev/null; then
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-${os}-${arch}.tar.gz" | tar -xz -C "$OUT"
    mv "$OUT/${os}-${arch}/helm" "$BIN/"
  fi
  if ! command -v kustomize >/dev/null; then
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_${os}_${arch}.tar.gz" | tar -xz -C "$BIN"
  fi
  if ! command -v kubeconform >/dev/null; then
    curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-${os}-${arch}.tar.gz" | tar -xz -C "$BIN" kubeconform
  fi
}

# Representative EKS values (the real ones come from Terraform).
cat > "$OUT/eks-values.yaml" <<'VALUES'
cloud: eks
clusterName: tf-eks-infra-dev
region: us-east-1
accountId: "123456789012"
vpcId: vpc-0123456789abcdef0
repoURL: https://github.com/yicheung/tf-eks-infra.git
targetRevision: main
registry:
  host: 123456789012.dkr.ecr.us-east-1.amazonaws.com
  prefix: tf-eks-infra
signer:
  issuer: https://token.actions.githubusercontent.com
  subjectRegExp: ^https://github\.com/yicheung/tf-eks-infra/\.github/workflows/image\.yml@refs/heads/main$
dns:
  domain: dev.example.com
  route53Zone: Z0123456789ABCDEFGHIJ
  acmeEmail: ops@example.com
  acmeStaging: true
alerts:
  snsTopicArn: arn:aws:sns:us-east-1:123456789012:tf-eks-infra-dev-security-alerts
storage:
  kmsKeyArn: arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000
monitoring:
  enabled: true
  alertsTopicArn: arn:aws:sns:us-east-1:123456789012:tf-eks-infra-dev-platform-alerts
VALUES

# Same cluster with the monitoring stack switched off (enable_monitoring = false).
sed -e 's/^  enabled: true$/  enabled: false/' -e 's/^  alertsTopicArn: .*/  alertsTopicArn: ""/' \
  "$OUT/eks-values.yaml" > "$OUT/eks-values-nomon.yaml"

render() {
  mkdir -p "$OUT/rendered"
  helm template root "$ROOT/platform/bootstrap" -f "$OUT/eks-values.yaml" > "$OUT/rendered/bootstrap.yaml"
  helm template root "$ROOT/platform/bootstrap" -f "$OUT/eks-values-nomon.yaml" > "$OUT/rendered/bootstrap-nomon.yaml"
  helm template policies "$ROOT/policies/kyverno" -f "$OUT/eks-values.yaml" \
    --set 'imageCredentialProviders={amazon}' > "$OUT/rendered/policies.yaml"
  for overlay in "$ROOT"/workloads/*/overlays/*; do
    name="$(basename "$(dirname "$(dirname "$overlay")")")-$(basename "$overlay")"
    kustomize build "$overlay" > "$OUT/rendered/workload-${name}.yaml"
  done
}

# CRDs missing from the community catalog (Kyverno CEL policies, ESO v1):
# convert the pinned upstream CRDs to strict JSON schemas.
crd_schemas() {
  mkdir -p "$ROOT/.schemas"
  local urls=(
    "https://raw.githubusercontent.com/kyverno/kyverno/v1.19.1/config/crds/policies.kyverno.io/policies.kyverno.io_validatingpolicies.yaml"
    "https://raw.githubusercontent.com/kyverno/kyverno/v1.19.1/config/crds/policies.kyverno.io/policies.kyverno.io_imagevalidatingpolicies.yaml"
    "https://raw.githubusercontent.com/kyverno/kyverno/v1.19.1/config/crds/policies.kyverno.io/policies.kyverno.io_generatingpolicies.yaml"
    "https://raw.githubusercontent.com/external-secrets/external-secrets/helm-chart-2.12.0/config/crds/bases/external-secrets.io_clustersecretstores.yaml"
    "https://raw.githubusercontent.com/external-secrets/external-secrets/helm-chart-2.12.0/config/crds/bases/external-secrets.io_externalsecrets.yaml"
    "https://raw.githubusercontent.com/external-secrets/external-secrets/helm-chart-2.12.0/config/crds/bases/generators.external-secrets.io_passwords.yaml"
  )
  for u in "${urls[@]}"; do curl -fsSL "$u" -o "$OUT/crd-$(basename "$u")"; done
  python3 - "$OUT" "$ROOT/.schemas" <<'PY'
import glob, json, sys, yaml
src, dst = sys.argv[1:]
def strict(s):
    if isinstance(s, dict):
        if s.get("type") == "object" and "properties" in s and "additionalProperties" not in s \
                and not s.get("x-kubernetes-preserve-unknown-fields"):
            s["additionalProperties"] = False
        for v in s.values():
            strict(v)
    elif isinstance(s, list):
        for v in s:
            strict(v)
for f in glob.glob(f"{src}/crd-*.yaml"):
    crd = yaml.safe_load(open(f))
    kind = crd["spec"]["names"]["kind"].lower()
    for v in crd["spec"]["versions"]:
        schema = v["schema"]["openAPIV3Schema"]
        strict(schema)
        json.dump(schema, open(f"{dst}/{kind}_{v['name']}.json", "w"))
PY
  rm -f "$OUT"/crd-*.yaml
}

validate() {
  local schemas=(
    -schema-location default
    # Pinned upstream CRDs converted above (take precedence)
    -schema-location "$ROOT/.schemas/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    # Community CRD schemas (Argo CD, cert-manager, Gateway API, Cilium)
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
  )
  kubeconform -strict -summary -output pretty \
    -kubernetes-version "$K8S_VERSION" \
    "${schemas[@]}" \
    ${KUBECONFORM_IGNORE_MISSING:+-ignore-missing-schemas} \
    "$OUT"/rendered/*.yaml
}

# Behavioural checks on the rendered output: the monitoring switch must add or
# remove the whole stack, including every chart's ServiceMonitor.
assert_monitoring_toggle() {
  python3 - "$OUT/rendered/bootstrap.yaml" "$OUT/rendered/bootstrap-nomon.yaml" <<'PY'
import sys, yaml, json
on, off = ([d for d in yaml.safe_load_all(open(f)) if d] for f in sys.argv[1:])
MON_KINDS = {"PodMonitor", "ServiceMonitor", "PrometheusRule", "StorageClass", "Password"}
MON_APPS = {"prometheus-operator-crds", "kube-prometheus-stack"}
METRIC_KEYS = ("servicemonitor", "serviceMonitor", "grafana")
def apps(docs): return {d["metadata"]["name"]: d for d in docs if d["kind"] == "Application"}
def inline(app):
    srcs = app["spec"].get("sources") or [app["spec"].get("source", {})]
    return json.dumps(srcs[0].get("helm", {}).get("valuesObject", {}))
fail = []
on_apps, off_apps = apps(on), apps(off)
if not MON_APPS <= on_apps.keys(): fail.append(f"monitoring on: missing apps {MON_APPS - on_apps.keys()}")
if MON_APPS & off_apps.keys(): fail.append(f"monitoring off: unexpected apps {MON_APPS & off_apps.keys()}")
if not MON_KINDS <= {d["kind"] for d in on}: fail.append(f"monitoring on: missing kinds {MON_KINDS - {d['kind'] for d in on}}")
if MON_KINDS & {d["kind"] for d in off}: fail.append(f"monitoring off: unexpected kinds {MON_KINDS & {d['kind'] for d in off}}")
if any(d["kind"] == "Namespace" and d["metadata"]["name"] == "monitoring" for d in off): fail.append("monitoring off: namespace still rendered")
for name in ("cert-manager", "external-secrets", "kyverno", "falco"):
    if not any(k in inline(on_apps[name]) for k in METRIC_KEYS): fail.append(f"monitoring on: {name} has no metrics values")
    if any(k in inline(off_apps[name]) for k in METRIC_KEYS): fail.append(f"monitoring off: {name} still enables metrics")
if "falcosidekick" not in inline(off_apps["falco"]): fail.append("monitoring off: Falco lost its SNS alert routing")
if fail:
    print("\n".join("FAIL " + f for f in fail)); sys.exit(1)
print(f"monitoring toggle: OK ({len(on)} resources on, {len(off)} off)")
PY
}

install_tools
crd_schemas
render
assert_monitoring_toggle
validate
