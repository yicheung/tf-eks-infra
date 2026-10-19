#!/usr/bin/env python3
"""Generate the tf-eks-infra architecture diagram in three formats from one model.

    python3 docs/architecture/generate_diagram.py

Writes, next to this script:
  tf-eks-infra-architecture.svg     vector image
  tf-eks-infra-architecture.drawio  diagrams.net / draw.io (editable)
  tf-eks-infra-architecture.vsdx    Microsoft Visio (editable)

The layout is hand-placed (pixel coordinates, origin top-left). Edit NODES and
EDGES below, then re-run. Standard library only.
"""
from __future__ import annotations

import html
import os
import zipfile
from dataclasses import dataclass, field

W, H = 2920, 1750
FONT = "Inter, 'Segoe UI', Helvetica, Arial, sans-serif"
OUT = os.path.dirname(os.path.abspath(__file__))
BASENAME = "tf-eks-infra-architecture"

# --------------------------------------------------------------------------- styles
# kind -> (fill, stroke, title colour, dashed)
STYLES = {
    "aws":     ("#FFFFFF", "#232F3E", "#232F3E", False),
    "group":   ("#F7F8FA", "#9AA5B1", "#232F3E", False),
    "vpc":     ("#F5FAF2", "#248814", "#1D6B10", False),
    "public":  ("#E9F4DA", "#7AA116", "#4A6B0A", False),
    "intra":   ("#EFE9FF", "#8C4FFF", "#5B2DB8", False),
    "private": ("#E6F1FA", "#147EBA", "#0E5A86", False),
    "nodes":   ("#FFFFFF", "#326CE5", "#1E4DB7", True),
    "cp":      ("#FFF4E0", "#E07B00", "#8A4B00", False),
    "svc":     ("#FFFFFF", "#545B64", "#232F3E", False),
    "sec":     ("#FDEDEF", "#DD344C", "#A3182C", False),
    "logs":    ("#FCEAF3", "#E7157B", "#9C0F53", False),
    "tf":      ("#F2ECFA", "#7B42BC", "#5A2D91", False),
    "argo":    ("#FDEFE7", "#E96D33", "#A6461A", False),
    "tenant":  ("#E7F6EC", "#1E8E3E", "#146C2E", False),
    "ext":     ("#F3F4F6", "#6B7280", "#374151", False),
    "warn":    ("#FFF8E1", "#C98A00", "#7A5300", True),
    "text":    (None, None, "#232F3E", False),
}
TEXT = "#2B3440"
MUTED = "#5B6573"

EDGE_COLORS = {
    "admin":   "#232F3E",
    "supply":  "#7B42BC",
    "inbound": "#147EBA",
    "egress":  "#4F8A10",
    "cp":      "#8C4FFF",
    "image":   "#E07B00",
    "logs":    "#E7157B",
    "alert":   "#DD344C",
}


@dataclass
class Node:
    id: str
    x: float
    y: float
    w: float
    h: float
    kind: str
    title: str = ""
    lines: list = field(default_factory=list)
    cols: int = 1            # lay `lines` out in N columns
    title_dx: float = 0      # shift the text block right (keeps lanes clear)
    title_size: float = 12.5
    size: float = 11
    container: bool = False  # drawn behind everything else, title only


@dataclass
class Edge:
    id: str
    src: str
    dst: str
    pts: list                # polyline, first point on src border, last on dst border
    kind: str
    num: int
    both: bool = False       # arrowheads at both ends
    badge_at: int = 0        # segment index for the number badge
    dashed: bool = False


NODES: list[Node] = []
EDGES: list[Edge] = []


def n(*a, **k):
    NODES.append(Node(*a, **k))


def e(*a, **k):
    EDGES.append(Edge(*a, **k))


# --------------------------------------------------------------------------- model
# Title row
n("title", 30, 18, 1500, 40, "text", "tf-eks-infra · secure EKS reference platform · envs/dev (project parallel, cluster parallel-dev)",
  title_size=22)
n("subtitle", 30, 52, 1800, 24, "text", "",
  ["Built from terraform plan: 130 resources to add (+ the one-time bootstrap stack). Everything inside the orange-bordered boxes is deployed afterwards by Argo CD from Git."],
  size=12.5)

# ---- left column: outside AWS
n("github", 30, 110, 340, 340, "group", "GitHub", container=True)
n("repo", 45, 145, 310, 120, "ext", "Repository yicheung/tf-eks-infra",
  ["terraform/ · platform/ · policies/", "workloads/ · app/sample", "Single source of truth for Argo CD"])
n("actions", 45, 280, 310, 155, "ext", "GitHub Actions",
  ["terraform: fmt, validate, test, plan", "image: Trivy gate, Syft SBOM,", "  cosign keyless sign, SLSA provenance",
   "manifests: kubeconform, Kyverno CLI", "AWS access via OIDC (no stored keys)"])
n("admin", 30, 480, 340, 125, "ext", "Admin workstation",
  ["Source IP 108.41.8.224/32", "IAM user yicheung / terraform-apply role", "terraform · kubectl · port-forward",
   "(move to an MFA admin role: audit)"])
n("internet", 30, 690, 340, 95, "ext", "Internet",
  ["Clients → HTTPS to the shared Gateway", "Outbound targets: GitHub, Helm repos,", "public images (via NAT)"])
n("email", 2440, 14, 400, 70, "ext", "Alert recipients (email)",
  ["security_alert_emails: subscribed", "platform_alert_emails: not set yet"])

# ---- AWS account
n("aws", 420, 100, 2460, 1590, "aws", "AWS account 906754897253 · us-east-1", container=True, title_size=15)

# top row: regional services
n("boot", 440, 150, 320, 320, "group", "Terraform bootstrap (one-time)", container=True)
n("state", 455, 185, 290, 120, "svc", "S3 state bucket",
  ["tf-eks-infra-tfstate-906754897253-", "us-east-1 · versioned · KMS", "keys: bootstrap/, envs/dev/", "S3-native lock (use_lockfile)"])
n("bootiam", 455, 315, 290, 140, "sec", "OIDC + CI roles (16 resources)",
  ["GitHub OIDC provider", "terraform-plan (ReadOnlyAccess)", "terraform-apply (AdministratorAccess)",
   "KMS key for state", "State is local until migrated"])

n("iam", 780, 150, 520, 320, "group", "IAM (roles created by this plan)", container=True)
n("eksroles", 795, 185, 240, 130, "sec", "EKS roles",
  ["cluster role + KMS policy", "node role: WorkerNode, ECR RO,", "  EKS_CNI_Policy (unused: M5)", "VPC flow-log role"])
n("ciroles", 1045, 185, 240, 130, "sec", "CI",
  ["ci-push role (GitHub OIDC)", "push to parallel/* only", "trust: main branch of this repo"])
n("podid", 795, 325, 490, 130, "sec", "EKS Pod Identity roles (one per ServiceAccount)",
  ["cilium-operator", "aws-load-balancer-controller", "external-secrets", "falcosidekick",
   "kyverno-admission", "alertmanager", "ebs-csi-controller", "cloudwatch-agent"], cols=2)

n("kms", 1320, 150, 260, 320, "sec", "KMS keys (customer-managed)",
  ["EKS secrets (envelope)", "CloudWatch logs", "EBS volumes", "ECR repository", "SNS security-alerts",
   "SNS platform-alerts", "", "EBS encryption by default", "(account-wide in us-east-1)"])

n("cw", 1600, 150, 400, 320, "group", "CloudWatch Logs", container=True)
n("cplogs", 1615, 185, 370, 95, "logs", "/aws/eks/parallel-dev/cluster",
  ["api · audit · authenticator ·", "controllerManager · scheduler · 365 d · KMS"])
n("flowlogs", 1615, 290, 370, 70, "logs", "VPC flow logs", ["all traffic · 365 d · KMS"])
n("ci_logs", 1615, 370, 370, 85, "logs", "Container Insights + container logs",
  ["CloudWatch Observability add-on", "(add-on-created log groups: audit L3)"])

n("reg", 2020, 150, 400, 320, "group", "Registry & secrets", container=True)
n("secrets", 2035, 185, 180, 270, "sec", "Secrets Manager",
  ["parallel-dev/*", "", "read by External", "Secrets via Pod", "Identity"])
n("ecr", 2230, 185, 175, 270, "svc", "Amazon ECR",
  ["parallel/sample-app", "immutable tags", "KMS · lifecycle", "enhanced scanning", "(Inspector)", "",
   "signatures, SBOM,", "provenance by digest"])

n("det", 2440, 150, 395, 320, "group", "Detection & alerting", container=True)
n("gd", 2455, 185, 180, 115, "sec", "GuardDuty",
  ["detector", "EKS audit-log monitoring", "Runtime Monitoring"])
n("eb", 2455, 320, 180, 135, "sec", "EventBridge rule",
  ["GuardDuty findings", "→ SNS security-alerts"])
n("snssec", 2645, 185, 175, 115, "sec", "SNS security-alerts",
  ["KMS · topic policy", "email subscription"])
n("snsplat", 2645, 320, 175, 135, "warn", "SNS platform-alerts",
  ["KMS · from Alertmanager", "no subscriber yet:", "set platform_alert_", "emails in tfvars"])

# EKS control plane (AWS-managed VPC)
n("cp", 440, 490, 1420, 120, "cp", "Amazon EKS control plane · parallel-dev · Kubernetes 1.36 (AWS-managed VPC)",
  ["API endpoint: public, restricted to 108.41.8.224/32, plus private · Secrets envelope-encrypted with KMS",
   "Access entries (API mode, no creator admin): terraform-apply role, user/yicheung → AmazonEKSClusterAdminPolicy",
   "bootstrap_self_managed_addons = false (no VPC CNI, no kube-proxy) · logs → CloudWatch · GuardDuty reads the audit stream",
   "Managed add-ons: eks-pod-identity-agent · coredns · aws-ebs-csi-driver · amazon-cloudwatch-observability"])

# VPC
n("vpc", 440, 635, 2390, 1035, "vpc", "VPC 10.0.0.0/16 · us-east-1a + us-east-1b · flow logs → CloudWatch · default SG / NACL locked down",
  container=True, title_size=13.5)
n("igw", 460, 700, 150, 70, "svc", "Internet gateway")
n("puba", 640, 680, 610, 110, "public", "", container=True)
n("puba_t", 800, 768, 300, 20, "text", "Public · us-east-1a · 10.0.96.0/24", title_size=11.5)
n("nlb", 660, 700, 240, 60, "svc", "Network Load Balancer",
  ["internet-facing · created by LB ctrl"], size=10.5)
n("nat", 920, 700, 240, 60, "svc", "NAT gateway + Elastic IP",
  ["single NAT for the dev VPC"], size=10.5)
n("pubb", 1270, 680, 610, 110, "public", "Public · us-east-1b · 10.0.97.0/24",
  ["NLB zone 1b · no NAT here (dev uses one NAT gateway)"], title_size=11.5, container=False)
n("s3ep", 2140, 680, 330, 70, "svc", "S3 gateway endpoint",
  ["image layers and S3 traffic skip the NAT"])
n("ebs", 2490, 680, 325, 70, "svc", "EBS gp3 volumes (KMS)",
  ["Prometheus 50 Gi · Alertmanager 5 Gi"])
n("intra", 1150, 810, 730, 60, "intra", "Intra subnets · 10.0.104.0/24 (1a) · 10.0.105.0/24 (1b) · no internet route",
  ["EKS control-plane ENIs ↔ nodes: 443, kubelet 10250, admission webhooks"], title_size=11.5)
n("sg", 2140, 765, 675, 105, "sec", "Security groups",
  ["cluster SG: 443 from nodes", "node SG (13 rules):", "  webhooks 4443/6443/8443/9443/10251",
   "  kubelet 10250, CoreDNS 53 tcp/udp", "  Cilium WireGuard + health ICMP", "  node ↔ node ephemeral, egress all"], cols=2)

n("priv", 460, 890, 2355, 765, "private", "Private subnets · 10.0.0.0/19 (1a) · 10.0.32.0/19 (1b) · default route → NAT",
  container=True, title_dx=1080, title_size=12)
n("ng", 480, 930, 2330, 710, "nodes",
  "EKS managed node group “system” · 2 × m7i.large (min 2, max 4) · Bottlerocket · IMDSv2 hop limit 1 · no SSH · pods get VPC IPs (Cilium ENI)",
  container=True, title_dx=320, title_size=12.5)

n("rowa", 810, 966, 700, 20, "text", "Installed by Terraform (helm_release / EKS add-on)", title_size=11.5)
n("addons", 500, 990, 260, 160, "tf", "EKS add-ons",
  ["eks-pod-identity-agent", "coredns", "aws-ebs-csi-driver", "  (Pod Identity, KMS)", "amazon-cloudwatch-", "  observability"])
n("cilium", 810, 990, 776, 160, "tf", "Cilium 1.20.3 · kube-system",
  ["ENI IPAM + kube-proxy replacement (eBPF)", "WireGuard pod-to-pod encryption", "Hubble relay + flow metrics",
   "Gateway API implementation (CRDs v1.6.3, vendored chart)", "operator: Pod Identity role for ENI management"])
n("argocd", 1606, 990, 378, 160, "tf", "Argo CD 10.10.5 · argocd",
  ["root app-of-apps (argocd-apps 2.0.6)", "AppProjects: platform vs app-* teams", "UI: port-forward only",
   "syncs platform/, policies/, workloads/"])
n("bottle", 2004, 990, 776, 160, "nodes", "Bottlerocket worker nodes",
  ["SELinux enforcing · immutable root · admin container via SSM",
   "launch template: IMDSv2 required, hop limit 1, encrypted root volume",
   "GuardDuty runtime agent (amazon-guardduty namespace)",
   "host-network pods: Cilium, Falco, node-exporter"])

n("rowb", 810, 1166, 700, 20, "text", "Deployed by Argo CD from Git (sync waves −1 → 3)", title_size=11.5)
n("gw", 500, 1190, 290, 210, "argo", "gateway-system · wave 2",
  ["shared Gateway (Cilium)", "HTTP → HTTPS redirect", "TLS: wildcard certificate", "  via cert-manager", "  (when a domain is set)",
   "the only way in for apps"])
n("certm", 810, 1190, 378, 210, "argo", "cert-manager · wave 0",
  ["ClusterIssuer letsencrypt (DNS-01)", "Gateway API support", "Route 53 access only when", "  a domain is configured"])
n("eso", 1208, 1190, 378, 210, "argo", "external-secrets · wave 0",
  ["ClusterSecretStore cloud-secrets", "  → Secrets Manager parallel-dev/*", "Password generator → grafana-admin",
   "Pod Identity role", "", "shared store: audit finding H2"])
n("kyv", 1606, 1190, 378, 210, "argo", "kyverno · wave 0",
  ["admission ×3 · background ×2", "cleanup ×2 · reports ×2", "verifies cosign signatures in ECR",
   "  (Pod Identity: ECR read)", "generates default-deny NetworkPolicies"])
n("mon", 2004, 1190, 776, 210, "argo", "monitoring · wave −1 (CRDs), wave 2 (stack)",
  ["prometheus-operator-crds 32.0.1 → kube-prometheus-stack 92.10.1",
   "Prometheus (15 d, 50 Gi) · Alertmanager (5 Gi) · Grafana (port-forward only)",
   "node-exporter · kube-state-metrics · ServiceMonitors for every chart",
   "StorageClass gp3-encrypted → EBS volumes (KMS)",
   "PrometheusRule platform-security (8 security alerts)",
   "Alertmanager → SNS platform-alerts (Pod Identity, SigV4)"])

n("app", 500, 1420, 290, 200, "tenant", "app-sample · wave 3",
  ["sample-app (Go, distroless)", "PSA restricted", "default-deny + DNS egress", "signed, digest-pinned image",
   "  from ECR parallel/sample-app", "HTTPRoute on the shared", "  Gateway"])
n("pol", 810, 1420, 378, 200, "argo", "policies (Kyverno CEL) · wave 2",
  ["tenant-namespace-psa-restricted", "require-hardened-containers", "restrict-image-source", "verify-image-signatures",
   "tenant-default-deny (generate)", "restrict-service-exposure"])
n("cfg", 1208, 1420, 378, 200, "argo", "Cluster config (root chart)",
  ["AppProject default (locked down)", "ClusterSecretStore cloud-secrets", "ClusterIssuer letsencrypt",
   "monitoring namespace + StorageClass", "grafana-admin ExternalSecret"])
n("lbc", 1606, 1420, 378, 200, "argo", "aws-load-balancer-controller · wave 0",
  ["kube-system · Pod Identity role", "provisions the NLB for the", "  shared Gateway Service"])
n("falco", 2004, 1420, 776, 200, "argo", "falco · wave 1",
  ["Falco DaemonSet (modern eBPF) on every node",
   "Falcosidekick ×2 → SNS security-alerts (Pod Identity, priority ≥ error)",
   "metrics → Prometheus · dashboards → Grafana",
   "rules: shells in containers, sensitive file reads, privilege changes"])

# Legend
n("legend", 30, 815, 340, 875, "group", "Legend", container=True)
LEG = [("svc", "AWS service"), ("sec", "Security / identity service"), ("logs", "Logging"),
       ("cp", "EKS control plane (AWS-managed)"), ("tf", "Installed by Terraform"),
       ("argo", "Deployed by Argo CD"), ("tenant", "Tenant workload"), ("ext", "Outside AWS"),
       ("warn", "Needs action")]
for i, (k, label) in enumerate(LEG):
    yy = 850 + i * 24
    n(f"leg_sw_{k}", 45, yy, 26, 16, k)
    n(f"leg_tx_{k}", 80, yy - 2, 270, 20, "text", label, title_size=11.5)

FLOWS = [
    ("admin", "Admin → EKS API (public endpoint, /32 only)"),
    ("admin", "terraform apply → state in S3 (lockfile)"),
    ("supply", "CI → OIDC → ci-push role → ECR: signed image, SBOM, SLSA provenance"),
    ("inbound", "Internet ↔ internet gateway"),
    ("inbound", "HTTPS in: IGW → NLB → shared Gateway"),
    ("inbound", "Gateway → tenant app (HTTPRoute)"),
    ("egress", "Egress: nodes → NAT → IGW (Git, Helm charts, public images)"),
    ("cp", "Control plane ↔ nodes through intra-subnet ENIs"),
    ("image", "Image pulls: ECR → nodes (layers via S3 endpoint); Kyverno checks signatures"),
    ("logs", "Control-plane, flow and container logs → CloudWatch"),
    ("alert", "Falcosidekick → SNS security-alerts"),
    ("alert", "Alertmanager → SNS platform-alerts"),
    ("alert", "GuardDuty finding → EventBridge → SNS security-alerts"),
    ("alert", "SNS security-alerts → email"),
]
n("leg_flows", 45, 1075, 320, 20, "text", "Flows", title_size=12.5)
fy = 1103
for i, (k, label) in enumerate(FLOWS, 1):
    n(f"leg_b{i}", 45, fy, 22, 22, "badge:" + k, str(i))
    # wrap at ~40 chars
    words, cur, out = label.split(), "", []
    for w_ in words:
        if len(cur) + len(w_) + 1 > 40:
            out.append(cur)
            cur = w_
        else:
            cur = (cur + " " + w_).strip()
    out.append(cur)
    n(f"leg_f{i}", 74, fy - 1, 290, 16 * len(out) + 4, "text", "", out, size=11)
    fy += 16 * len(out) + 10

n("footer", 30, 1706, 2800, 30, "text", "",
  ["Not shown as boxes: route tables and associations, EKS access-policy associations, IAM policy attachments, KMS aliases, ECR lifecycle policy, "
   "SNS topic policy, ec2 tags, time_sleep. Every resource is tagged Project / Environment / Owner / ManagedBy / Repository. "
   "Source: docs/architecture/generate_diagram.py."], size=11)

# --------------------------------------------------------------------------- edges
e("e1", "admin", "cp", [(370, 550), (440, 550)], "admin", 1)
e("e2", "admin", "state", [(370, 505), (395, 505), (395, 245), (455, 245)], "admin", 2, badge_at=1)
e("e3", "actions", "ecr", [(355, 330), (382, 330), (382, 90), (2318, 90), (2318, 185)], "supply", 3, badge_at=2)
e("e4", "internet", "igw", [(370, 735), (460, 735)], "inbound", 4, both=True)
e("e5a", "igw", "nlb", [(610, 730), (660, 730)], "inbound", 5)
e("e5b", "nlb", "gw", [(780, 760), (780, 1190)], "inbound", 5)
e("e6", "gw", "app", [(645, 1400), (645, 1420)], "inbound", 6)
e("e7a", "ng", "nat", [(1120, 930), (1120, 760)], "egress", 7)
e("e7b", "nat", "igw", [(1040, 700), (1040, 690), (535, 690), (535, 700)], "egress", 7, badge_at=1)
e("e8a", "cp", "intra", [(1260, 610), (1260, 810)], "cp", 8, both=True)
e("e8b", "intra", "ng", [(1500, 870), (1500, 930)], "cp", 8, both=True)
e("e9", "ecr", "ng", [(2318, 455), (2318, 480), (2100, 480), (2100, 930)], "image", 9, badge_at=2)
e("e10", "cp", "cplogs", [(1800, 490), (1800, 455)], "logs", 10)
e("e11", "falco", "snssec", [(2780, 1530), (2862, 1530), (2862, 243), (2820, 243)], "alert", 11, badge_at=1)
e("e12", "mon", "snsplat", [(2780, 1300), (2848, 1300), (2848, 390), (2820, 390)], "alert", 12, badge_at=1)
e("e13a", "gd", "eb", [(2545, 300), (2545, 320)], "alert", 13)
e("e13b", "eb", "snssec", [(2635, 390), (2640, 390), (2640, 270), (2645, 270)], "alert", 13, badge_at=-1)
e("e14", "snssec", "email", [(2732, 185), (2732, 84)], "alert", 14)

# Badge placement overrides (some segments are too short for a centred badge)
BADGE_POS = {"e5a": (635, 712), "e6": (668, 1410), "e8b": (1522, 900), "e10": (1822, 474),
             "e13a": (2568, 310), "e13b": (2625, 300), "e1": (405, 532), "e4": (415, 717)}


# --------------------------------------------------------------------------- helpers
def by_id(i):
    return next(x for x in NODES if x.id == i)


def text_rows(nd: Node):
    """Return (x, y, text, size, bold, colour) rows relative to the canvas."""
    rows = []
    fill, stroke, tcol, _ = STYLES.get(nd.kind, STYLES["text"]) if not nd.kind.startswith("badge") else (None, None, "#fff", 0)
    x0 = nd.x + 8 + nd.title_dx
    y = nd.y + 6
    if nd.title:
        y += nd.title_size + 2
        rows.append((x0, y, nd.title, nd.title_size, True, tcol))
        y += 4
    lh = nd.size * 1.4
    if nd.cols == 1:
        for ln in nd.lines:
            y += lh
            rows.append((x0, y, ln, nd.size, False, TEXT))
    else:
        per = -(-len(nd.lines) // nd.cols)
        colw = (nd.w - 16) / nd.cols
        for ci in range(nd.cols):
            yy = y
            for ln in nd.lines[ci * per:(ci + 1) * per]:
                yy += lh
                rows.append((x0 + ci * colw, yy, ln, nd.size, False, TEXT))
    return rows


def badge_point(ed: Edge):
    if ed.id in BADGE_POS:
        return BADGE_POS[ed.id]
    i = ed.badge_at if ed.badge_at >= 0 else len(ed.pts) - 2
    (x1, y1), (x2, y2) = ed.pts[i], ed.pts[i + 1]
    return ((x1 + x2) / 2, (y1 + y2) / 2)


def check_fit():
    """Warn when text would overflow its box (measured with Inter if available)."""
    try:
        from PIL import ImageFont
        reg = "/usr/share/fonts/opentype/inter/Inter-Regular.otf"
        bold = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"
        cache = {}

        def width(t, s, b):
            key = (s, b)
            if key not in cache:
                cache[key] = ImageFont.truetype(bold if b else reg, int(round(s * 4)))
            return cache[key].getlength(t) / 4
    except Exception:
        return
    for nd in NODES:
        if nd.kind == "text" or nd.kind.startswith("badge"):
            continue
        colw = (nd.w - 16) / nd.cols
        for (x, y, t, s, b, _) in text_rows(nd):
            limit = (nd.x + nd.w - 6) - x if b or nd.cols == 1 else colw - 6
            if width(t, s, b) > limit:
                print(f"  overflow: {nd.id}: {t!r} ({width(t, s, b):.0f} > {limit:.0f})")
        last_y = max((r[1] for r in text_rows(nd)), default=nd.y)
        if not nd.container and last_y + 6 > nd.y + nd.h:
            print(f"  too tall: {nd.id} ({last_y + 6:.0f} > {nd.y + nd.h})")


def ordered_nodes():
    return [x for x in NODES if x.container] + [x for x in NODES if not x.container]


# --------------------------------------------------------------------------- SVG
def svg():
    esc = html.escape
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
         f'font-family="{esc(FONT)}">',
         "<title>tf-eks-infra architecture (envs/dev)</title>",
         "<defs>"]
    for k, c in EDGE_COLORS.items():
        o.append(f'<marker id="a-{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                 f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
    o.append("</defs>")
    o.append(f'<rect width="{W}" height="{H}" fill="#FFFFFF"/>')
    for nd in ordered_nodes():
        if nd.kind.startswith("badge"):
            continue
        fill, stroke, _, dashed = STYLES[nd.kind]
        if stroke:
            sw = 2 if nd.kind in ("aws", "vpc") else 1.3
            dash = ' stroke-dasharray="6 4"' if dashed else ""
            o.append(f'<rect x="{nd.x}" y="{nd.y}" width="{nd.w}" height="{nd.h}" rx="8" fill="{fill}" '
                     f'stroke="{stroke}" stroke-width="{sw}"{dash}/>')
        for (x, y, t, s, b, col) in text_rows(nd):
            if not t:
                continue
            o.append(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{s}" font-weight="{600 if b else 400}" '
                     f'fill="{col}" xml:space="preserve">{esc(t)}</text>')
    for ed in EDGES:
        c = EDGE_COLORS[ed.kind]
        d = " ".join(f"{x},{y}" for x, y in ed.pts)
        ms = f' marker-start="url(#a-{ed.kind})"' if ed.both else ""
        dash = ' stroke-dasharray="6 4"' if ed.dashed else ""
        o.append(f'<polyline points="{d}" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"'
                 f'{dash}{ms} marker-end="url(#a-{ed.kind})"/>')
    for ed in EDGES:
        bx, by = badge_point(ed)
        o.append(badge_svg(bx, by, ed.num, EDGE_COLORS[ed.kind]))
    for nd in NODES:
        if nd.kind.startswith("badge"):
            k = nd.kind.split(":")[1]
            o.append(badge_svg(nd.x + nd.w / 2, nd.y + nd.h / 2, nd.title, EDGE_COLORS[k]))
    o.append("</svg>")
    return "\n".join(o)


def badge_svg(x, y, num, col):
    return (f'<g><circle cx="{x}" cy="{y}" r="11" fill="{col}" stroke="#FFFFFF" stroke-width="2"/>'
            f'<text x="{x}" y="{y + 4}" text-anchor="middle" font-size="11" font-weight="700" fill="#FFFFFF">{num}</text></g>')


# --------------------------------------------------------------------------- draw.io
def drawio():
    esc = lambda s: html.escape(s, quote=True)
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    for nd in ordered_nodes():
        if nd.kind.startswith("badge"):
            k = nd.kind.split(":")[1]
            cells.append(badge_drawio(nd.id, nd.x + nd.w / 2, nd.y + nd.h / 2, nd.title, EDGE_COLORS[k]))
            continue
        fill, stroke, tcol, dashed = STYLES[nd.kind]
        parts = []
        if nd.title:
            parts.append(f'<b><font style="font-size:{nd.title_size:g}px" color="{tcol}">{html.escape(nd.title)}</font></b>')
        if nd.cols > 1:
            per = -(-len(nd.lines) // nd.cols)
            cols_html = []
            for ci in range(nd.cols):
                cols_html.append("<td style=\"vertical-align:top;padding-right:16px\">" +
                                 "<br>".join(html.escape(l) for l in nd.lines[ci * per:(ci + 1) * per]) + "</td>")
            parts.append("<table style=\"font-size:inherit\"><tr>" + "".join(cols_html) + "</tr></table>")
        elif nd.lines:
            parts.append("<br>".join(html.escape(l).replace("  ", "&nbsp;&nbsp;") for l in nd.lines))
        value = "<br>".join(parts[:1]) + ("<br>" + parts[1] if len(parts) > 1 else "")
        style = ["whiteSpace=wrap", "html=1", "align=left", "verticalAlign=top", f"fontSize={nd.size:g}",
                 f"fontColor={TEXT}", "fontFamily=Helvetica", f"spacingLeft={6 + nd.title_dx:g}", "spacingTop=2"]
        if stroke:
            style += ["rounded=1", "arcSize=4" if nd.container or nd.w > 400 else "arcSize=8",
                      f"fillColor={fill}", f"strokeColor={stroke}",
                      f"strokeWidth={2 if nd.kind in ('aws', 'vpc') else 1.3}"]
            if dashed:
                style.append("dashed=1")
        else:
            style += ["text", "fillColor=none", "strokeColor=none"]
        if nd.container:
            style.append("container=0")
        cells.append(f'<mxCell id="{nd.id}" value="{esc(value)}" style="{";".join(style)};" vertex="1" parent="1">'
                     f'<mxGeometry x="{nd.x}" y="{nd.y}" width="{nd.w}" height="{nd.h}" as="geometry"/></mxCell>')
    for ed in EDGES:
        s, t = by_id(ed.src), by_id(ed.dst)
        (sx, sy), (tx, ty) = ed.pts[0], ed.pts[-1]
        style = ["html=1", "rounded=0", "edgeStyle=none", f"strokeColor={EDGE_COLORS[ed.kind]}", "strokeWidth=2",
                 "endArrow=block", "endFill=1",
                 f"exitX={(sx - s.x) / s.w:.4f}", f"exitY={(sy - s.y) / s.h:.4f}", "exitDx=0", "exitDy=0", "exitPerimeter=0",
                 f"entryX={(tx - t.x) / t.w:.4f}", f"entryY={(ty - t.y) / t.h:.4f}", "entryDx=0", "entryDy=0", "entryPerimeter=0"]
        style.append("startArrow=block;startFill=1" if ed.both else "startArrow=none")
        if ed.dashed:
            style.append("dashed=1")
        pts = "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in ed.pts[1:-1])
        cells.append(f'<mxCell id="{ed.id}" style="{";".join(style)};" edge="1" parent="1" source="{ed.src}" target="{ed.dst}">'
                     f'<mxGeometry relative="1" as="geometry"><mxPoint x="{sx}" y="{sy}" as="sourcePoint"/>'
                     f'<mxPoint x="{tx}" y="{ty}" as="targetPoint"/><Array as="points">{pts}</Array></mxGeometry></mxCell>')
        bx, by = badge_point(ed)
        cells.append(badge_drawio(f"{ed.id}_n", bx, by, ed.num, EDGE_COLORS[ed.kind]))
    return ('<mxfile host="drawio" type="device">\n'
            '<diagram id="tf-eks-infra" name="tf-eks-infra (envs/dev)">\n'
            f'<mxGraphModel dx="1400" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
            f'fold="1" page="1" pageScale="1" pageWidth="{W}" pageHeight="{H}" math="0" shadow="0" background="#FFFFFF">\n'
            "<root>\n" + "\n".join(cells) + "\n</root>\n</mxGraphModel>\n</diagram>\n</mxfile>\n")


def badge_drawio(cid, x, y, num, col):
    style = (f"ellipse;html=1;whiteSpace=wrap;fillColor={col};strokeColor=#FFFFFF;strokeWidth=2;"
             "fontColor=#FFFFFF;fontStyle=1;fontSize=11;align=center;verticalAlign=middle;")
    return (f'<mxCell id="{cid}" value="{num}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x - 11}" y="{y - 11}" width="22" height="22" as="geometry"/></mxCell>')


# --------------------------------------------------------------------------- Visio (.vsdx)
PX = 1 / 96.0  # inches per pixel
NS = "http://schemas.microsoft.com/office/visio/2012/main"
RNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def vx(x):
    return x * PX


def vy(y):
    return (H - y) * PX


def cell(name, v, u=None):
    uu = f' U="{u}"' if u else ""
    return f'<Cell N="{name}" V="{v}"{uu}/>'


def vsd_text_shape(sid, nd: Node):
    """2D rounded rectangle with a bold title run and a regular body run."""
    fill, stroke, tcol, dashed = STYLES[nd.kind]
    w, h = nd.w * PX, nd.h * PX
    cx, cy = vx(nd.x + nd.w / 2), vy(nd.y + nd.h / 2)
    c = [cell("PinX", f"{cx:.4f}"), cell("PinY", f"{cy:.4f}"), cell("Width", f"{w:.4f}"), cell("Height", f"{h:.4f}"),
         cell("LocPinX", f"{w / 2:.4f}"), cell("LocPinY", f"{h / 2:.4f}"),
         cell("LeftMargin", f"{(6 + nd.title_dx) * PX:.4f}"), cell("RightMargin", f"{4 * PX:.4f}"),
         cell("TopMargin", f"{4 * PX:.4f}"), cell("BottomMargin", f"{2 * PX:.4f}"),
         cell("VerticalAlign", "0"), cell("TextDirection", "0")]
    if stroke:
        c += [cell("FillForegnd", fill), cell("FillPattern", "1"), cell("LineColor", stroke),
              cell("LineWeight", f"{(2 if nd.kind in ('aws', 'vpc') else 1.3) * PX:.4f}"),
              cell("LinePattern", "2" if dashed else "1"), cell("Rounding", f"{(4 if nd.w > 400 else 6) * PX:.4f}")]
    else:
        c += [cell("FillPattern", "0"), cell("LinePattern", "0")]
    body = nd.lines
    if nd.cols > 1:
        per = -(-len(nd.lines) // nd.cols)
        colsets = [nd.lines[i * per:(i + 1) * per] for i in range(nd.cols)]
        body = ["      ".join(f"{(cs[r] if r < len(cs) else ''):<30}" for cs in colsets).rstrip()
                for r in range(per)]
    t_style, t_col, t_size = ("1", tcol, nd.title_size) if nd.title else ("0", TEXT, nd.size)
    chars = [f'<Row IX="0">{cell("Font", "Arial")}{cell("Color", t_col)}{cell("Style", t_style)}'
             f'{cell("Size", f"{t_size * 0.75 / 72:.4f}")}</Row>',
             f'<Row IX="1">{cell("Font", "Arial")}{cell("Color", TEXT)}{cell("Style", "0")}'
             f'{cell("Size", f"{nd.size * 0.75 / 72:.4f}")}</Row>']
    para = f'<Section N="Paragraph"><Row IX="0">{cell("HorzAlign", "0")}{cell("SpLine", "-1.2")}</Row></Section>'
    txt = ""
    if nd.title:
        txt += f'<cp IX="0"/>{html.escape(nd.title)}'
    if body:
        # Switch runs before the line break, so a renderer that applies the run
        # change one character late only affects the newline.
        txt += (f'<cp IX="1"/>\n' if nd.title else "") + html.escape("\n".join(body))
    geom = rect_geom(w, h, nofill=not stroke)
    return (f'<Shape ID="{sid}" NameU="{nd.id}" Name="{nd.id}" Type="Shape" LineStyle="0" FillStyle="0" TextStyle="0">'
            + "".join(c) + f'<Section N="Character">{"".join(chars)}</Section>' + para + geom
            + (f"<Text>{txt}</Text>" if txt else "") + "</Shape>")


def rect_geom(w, h, nofill=False):
    rows = [("MoveTo", 0, 0), ("LineTo", w, 0), ("LineTo", w, h), ("LineTo", 0, h), ("LineTo", 0, 0)]
    r = "".join(f'<Row T="{t}" IX="{i + 1}">{cell("X", f"{x:.4f}")}{cell("Y", f"{y:.4f}")}</Row>'
                for i, (t, x, y) in enumerate(rows))
    return (f'<Section N="Geometry" IX="0">{cell("NoFill", "1" if nofill else "0")}{cell("NoLine", "1" if nofill else "0")}'
            f'{cell("NoShow", "0")}{r}</Section>')


def vsd_badge(sid, x, y, num, col):
    d = 22 * PX
    return (f'<Shape ID="{sid}" NameU="badge{sid}" Type="Shape" LineStyle="0" FillStyle="0" TextStyle="0">'
            + cell("PinX", f"{vx(x):.4f}") + cell("PinY", f"{vy(y):.4f}") + cell("Width", f"{d:.4f}")
            + cell("Height", f"{d:.4f}") + cell("LocPinX", f"{d / 2:.4f}") + cell("LocPinY", f"{d / 2:.4f}")
            + cell("FillForegnd", col) + cell("FillPattern", "1") + cell("LineColor", "#FFFFFF")
            + cell("LineWeight", f"{2 * PX:.4f}") + cell("VerticalAlign", "1")
            + cell("LeftMargin", "0") + cell("RightMargin", "0") + cell("TopMargin", "0") + cell("BottomMargin", "0")
            + f'<Section N="Character"><Row IX="0">{cell("Font", "Arial")}{cell("Color", "#FFFFFF")}{cell("Style", "1")}'
            f'{cell("Size", f"{8 / 72:.4f}")}</Row></Section>'
            + f'<Section N="Paragraph"><Row IX="0">{cell("HorzAlign", "1")}</Row></Section>'
            + f'<Section N="Geometry" IX="0">{cell("NoFill", "0")}{cell("NoLine", "0")}{cell("NoShow", "0")}'
            f'<Row T="Ellipse" IX="1">{cell("X", f"{d / 2:.4f}")}{cell("Y", f"{d / 2:.4f}")}{cell("A", f"{d:.4f}")}'
            f'{cell("B", f"{d / 2:.4f}")}{cell("C", f"{d / 2:.4f}")}{cell("D", f"{d:.4f}")}</Row></Section>'
            + f"<Text>{num}</Text></Shape>")


def vsd_edge(sid, ed: Edge):
    xs = [p[0] for p in ed.pts]
    ys = [p[1] for p in ed.pts]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    w, h = max(maxx - minx, 1) * PX, max(maxy - miny, 1) * PX
    cx, cy = vx((minx + maxx) / 2), vy((miny + maxy) / 2)
    rows = []
    for i, (x, y) in enumerate(ed.pts):
        lx, ly = (x - minx) * PX, (maxy - y) * PX
        rows.append(f'<Row T="{"MoveTo" if i == 0 else "LineTo"}" IX="{i + 1}">{cell("X", f"{lx:.4f}")}{cell("Y", f"{ly:.4f}")}</Row>')
    col = EDGE_COLORS[ed.kind]
    return (f'<Shape ID="{sid}" NameU="{ed.id}" Name="{ed.id}" Type="Shape" LineStyle="0" FillStyle="0" TextStyle="0">'
            + cell("PinX", f"{cx:.4f}") + cell("PinY", f"{cy:.4f}") + cell("Width", f"{w:.4f}") + cell("Height", f"{h:.4f}")
            + cell("LocPinX", f"{w / 2:.4f}") + cell("LocPinY", f"{h / 2:.4f}")
            + cell("LineColor", col) + cell("LineWeight", f"{2 * PX:.4f}") + cell("LinePattern", "2" if ed.dashed else "1")
            + cell("EndArrow", "4") + cell("EndArrowSize", "1") + cell("BeginArrow", "4" if ed.both else "0")
            + cell("BeginArrowSize", "1") + cell("FillPattern", "0")
            + f'<Section N="Geometry" IX="0">{cell("NoFill", "1")}{cell("NoLine", "0")}{cell("NoShow", "0")}'
            + "".join(rows) + "</Section></Shape>")


def vsdx(path):
    shapes, sid = [], 1
    for nd in ordered_nodes():
        if nd.kind.startswith("badge"):
            k = nd.kind.split(":")[1]
            shapes.append(vsd_badge(sid, nd.x + nd.w / 2, nd.y + nd.h / 2, nd.title, EDGE_COLORS[k]))
        else:
            shapes.append(vsd_text_shape(sid, nd))
        sid += 1
    for ed in EDGES:
        shapes.append(vsd_edge(sid, ed))
        sid += 1
    for ed in EDGES:
        bx, by = badge_point(ed)
        shapes.append(vsd_badge(sid, bx, by, ed.num, EDGE_COLORS[ed.kind]))
        sid += 1

    page = (f'<?xml version="1.0" encoding="utf-8"?>\n<PageContents xmlns="{NS}" xmlns:r="{RNS}" xml:space="preserve">'
            f'<Shapes>{"".join(shapes)}</Shapes></PageContents>')
    pages = (f'<?xml version="1.0" encoding="utf-8"?>\n<Pages xmlns="{NS}" xmlns:r="{RNS}" xml:space="preserve">'
             f'<Page ID="0" NameU="Architecture" Name="Architecture" ViewScale="-1" ViewCenterX="{W * PX / 2:.4f}" '
             f'ViewCenterY="{H * PX / 2:.4f}"><PageSheet LineStyle="0" FillStyle="0" TextStyle="0">'
             f'{cell("PageWidth", f"{W * PX:.4f}")}{cell("PageHeight", f"{H * PX:.4f}")}'
             f'{cell("ShdwOffsetX", "0.125")}{cell("ShdwOffsetY", "-0.125")}{cell("PageScale", "1", "IN")}'
             f'{cell("DrawingScale", "1", "IN")}{cell("DrawingSizeType", "3")}{cell("DrawingScaleType", "0")}'
             f'{cell("InhibitSnap", "0")}{cell("PrintPageOrientation", "2")}'
             f'</PageSheet><Rel r:id="rId1"/></Page></Pages>')
    stylesheet = (f'<StyleSheet ID="0" NameU="No Style" Name="No Style">'
                  f'{cell("EnableLineProps", "1")}{cell("EnableFillProps", "1")}{cell("EnableTextProps", "1")}'
                  f'{cell("LineWeight", "0.01041666666666667")}{cell("LineColor", "0")}{cell("LinePattern", "1")}'
                  f'{cell("Rounding", "0")}{cell("EndArrowSize", "2")}{cell("BeginArrow", "0")}{cell("EndArrow", "0")}'
                  f'{cell("LineCap", "0")}{cell("BeginArrowSize", "2")}{cell("LineColorTrans", "0")}'
                  f'{cell("FillForegnd", "1")}{cell("FillBkgnd", "0")}{cell("FillPattern", "1")}'
                  f'{cell("ShdwForegnd", "0")}{cell("ShdwPattern", "0")}{cell("FillForegndTrans", "0")}'
                  f'{cell("LeftMargin", "0")}{cell("RightMargin", "0")}{cell("TopMargin", "0")}{cell("BottomMargin", "0")}'
                  f'{cell("VerticalAlign", "1")}{cell("TextBkgnd", "0")}{cell("DefaultTabStop", "0.5")}'
                  f'{cell("TextDirection", "0")}'
                  f'<Section N="Character"><Row IX="0">{cell("Font", "Arial")}{cell("Color", "0")}{cell("Style", "0")}'
                  f'{cell("Size", "0.1111111111111111")}</Row></Section>'
                  f'<Section N="Paragraph"><Row IX="0">{cell("HorzAlign", "1")}{cell("SpLine", "-1.2")}</Row></Section>'
                  f'</StyleSheet>')
    document = (f'<?xml version="1.0" encoding="utf-8"?>\n<VisioDocument xmlns="{NS}" xmlns:r="{RNS}" xml:space="preserve">'
                f'<DocumentSettings TopPage="0" DefaultTextStyle="0" DefaultLineStyle="0" DefaultFillStyle="0" '
                f'DefaultGuideStyle="0"><GlueSettings>9</GlueSettings><SnapSettings>65847</SnapSettings>'
                f'<SnapExtensions>34</SnapExtensions><DynamicGridEnabled>0</DynamicGridEnabled>'
                f'<ProtectStyles>0</ProtectStyles><ProtectShapes>0</ProtectShapes><ProtectMasters>0</ProtectMasters>'
                f'<ProtectBkgnds>0</ProtectBkgnds></DocumentSettings>'
                f'<Colors><ColorEntry IX="0" RGB="#000000"/><ColorEntry IX="1" RGB="#FFFFFF"/></Colors>'
                f'<FaceNames><FaceName NameU="Arial" UnicodeRanges="-1610612033 1073772795 9 0" CharSets="1073742335 -65536" '
                f'Panos="2 11 6 4 2 2 2 2 2 4" Flags="325"/></FaceNames>'
                f'<StyleSheets>{stylesheet}</StyleSheets></VisioDocument>')
    windows = (f'<?xml version="1.0" encoding="utf-8"?>\n<Windows ClientWidth="1600" ClientHeight="900" xmlns="{NS}" '
               f'xmlns:r="{RNS}" xml:space="preserve"><Window ID="0" WindowType="Drawing" WindowState="1073741824" '
               f'ClientWidth="1600" ClientHeight="900" ContainerType="Page" Page="0" ViewScale="-1" '
               f'ViewCenterX="{W * PX / 2:.4f}" ViewCenterY="{H * PX / 2:.4f}"><ShowRulers>1</ShowRulers>'
               f'<ShowGrid>0</ShowGrid><ShowPageBreaks>0</ShowPageBreaks><ShowGuides>1</ShowGuides>'
               f'<ShowConnectionPoints>1</ShowConnectionPoints><GlueSettings>9</GlueSettings>'
               f'<SnapSettings>65847</SnapSettings><SnapExtensions>34</SnapExtensions>'
               f'<DynamicGridEnabled>0</DynamicGridEnabled><TabSplitterPos>0.5</TabSplitterPos></Window></Windows>')
    ct = ('<?xml version="1.0" encoding="utf-8"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/visio/document.xml" ContentType="application/vnd.ms-visio.drawing.main+xml"/>'
          '<Override PartName="/visio/pages/pages.xml" ContentType="application/vnd.ms-visio.pages+xml"/>'
          '<Override PartName="/visio/pages/page1.xml" ContentType="application/vnd.ms-visio.page+xml"/>'
          '<Override PartName="/visio/windows.xml" ContentType="application/vnd.ms-visio.windows+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
          '</Types>')
    rels = ('<?xml version="1.0" encoding="utf-8"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/document" Target="visio/document.xml"/>'
            '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
            '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
            '</Relationships>')
    doc_rels = ('<?xml version="1.0" encoding="utf-8"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/pages" Target="pages/pages.xml"/>'
                '<Relationship Id="rId2" Type="http://schemas.microsoft.com/visio/2010/relationships/windows" Target="windows.xml"/>'
                '</Relationships>')
    pages_rels = ('<?xml version="1.0" encoding="utf-8"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                  '<Relationship Id="rId1" Type="http://schemas.microsoft.com/visio/2010/relationships/page" Target="page1.xml"/>'
                  '</Relationships>')
    core = ('<?xml version="1.0" encoding="utf-8"?>\n<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>tf-eks-infra architecture (envs/dev)</dc:title>'
            '<dc:creator>tf-eks-infra</dc:creator></cp:coreProperties>')
    app = ('<?xml version="1.0" encoding="utf-8"?>\n<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
           '<Application>Microsoft Visio</Application><AppVersion>16.0000</AppVersion></Properties>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ct)
        z.writestr("_rels/.rels", rels)
        z.writestr("docProps/core.xml", core)
        z.writestr("docProps/app.xml", app)
        z.writestr("visio/document.xml", document)
        z.writestr("visio/_rels/document.xml.rels", doc_rels)
        z.writestr("visio/windows.xml", windows)
        z.writestr("visio/pages/pages.xml", pages)
        z.writestr("visio/pages/_rels/pages.xml.rels", pages_rels)
        z.writestr("visio/pages/page1.xml", page)


if __name__ == "__main__":
    check_fit()
    with open(os.path.join(OUT, BASENAME + ".svg"), "w", encoding="utf-8") as f:
        f.write(svg())
    with open(os.path.join(OUT, BASENAME + ".drawio"), "w", encoding="utf-8") as f:
        f.write(drawio())
    vsdx(os.path.join(OUT, BASENAME + ".vsdx"))
    print("wrote", ", ".join(BASENAME + x for x in (".svg", ".drawio", ".vsdx")))
