#!/usr/bin/env bash
# Re-vendor the Gateway API standard-channel CRDs Terraform installs before Cilium.
# Usage: scripts/update-gateway-api-crds.sh v1.6.3
set -euo pipefail
VERSION="${1:?usage: $0 <gateway-api version, e.g. v1.6.3>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/terraform/modules/aws/eks-cni/charts/gateway-api-crds"
mkdir -p "$CHART/templates"
curl -fsSL "https://github.com/kubernetes-sigs/gateway-api/releases/download/${VERSION}/standard-install.yaml" \
  -o "$CHART/templates/standard-install.yaml"
if grep -q '{{' "$CHART/templates/standard-install.yaml"; then
  echo "CRDs contain '{{' and would break Helm templating; escape them before committing." >&2
  exit 1
fi
sed -i.bak -E "s/^(version|appVersion): .*/\1: ${VERSION#v}/" "$CHART/Chart.yaml" && rm -f "$CHART/Chart.yaml.bak"
sed -i.bak -E "s/^appVersion: .*/appVersion: ${VERSION}/" "$CHART/Chart.yaml" && rm -f "$CHART/Chart.yaml.bak"
echo "Vendored Gateway API ${VERSION} into $CHART"
