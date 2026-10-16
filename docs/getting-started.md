# Getting started (EKS)

> For the exact first-time commands (bootstrap, state migration, tfvars values, the two-pass first apply, and troubleshooting), follow **[TF-init-deployment.md](TF-init-deployment.md)**. This page gives the overview and covers what comes after.

## Prerequisites

- Terraform ≥ 1.10 (S3-native state locking), AWS CLI v2, kubectl
- An AWS account and an admin identity, e.g. an IAM Identity Center role
- A GitHub repository for this code (default `yicheung/tf-eks-infra`)
- Optional: a Route 53 hosted zone for public TLS

## 1. Bootstrap (once per account)

```bash
cd terraform/bootstrap
terraform init
terraform apply -var github_repository=yicheung/tf-eks-infra
```

This creates the KMS-encrypted, TLS-only state bucket, the GitHub OIDC provider, and two CI roles:
- **plan**: read-only, usable from PRs
- **apply**: only from the protected `dev` GitHub Environment

Then move bootstrap's own state into the bucket. Write a `backend.tf` that points at it (exact commands in [TF-init-deployment.md](TF-init-deployment.md#2-move-bootstraps-state-into-the-bucket-it-just-created)) and run:

```bash
terraform init -migrate-state
```

## 2. Configure the dev environment

1. In `terraform/envs/dev/backend.tf`, set `bucket` to the `state_bucket_name` output.
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill it in. It holds no secrets (ARNs, CIDRs), so commit it so CI can plan.
   - `cluster_admin_principal_arns` **must** include the identity running Terraform: your SSO role for local applies, the `terraform-apply` role for CI. There is no implicit creator-admin.
   - `api_public_access_cidrs`: your egress IP `/32`, or `[]` for private-only. With private-only, Terraform must run from inside the VPC.

## 3. Apply

```bash
cd terraform/envs/dev
terraform init
terraform apply -target=module.network -target=module.eks   # first run only: cluster before Helm
terraform apply
```

Order of operations, which Terraform handles:
1. VPC
2. EKS: no add-ons, so no aws-node or kube-proxy
3. Gateway API CRDs
4. Cilium
5. CoreDNS
6. Pod Identity roles, ECR, GuardDuty
7. Argo CD and the root Application

Allow about 25–35 minutes.

## 4. Watch GitOps take over

```bash
$(terraform output -raw kubeconfig_command)
kubectl -n argocd get applications -w
terraform output -raw argocd_ui_command   # then https://localhost:8080
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Sync waves:
- **Wave 0:** cert-manager, ESO, Kyverno, AWS LB Controller
- **Wave 1:** Falco
- **Wave 2:** policies, ClusterSecretStore/Issuer, shared Gateway
- **Wave 3:** sample app

## 5. Wire up CI

Set these GitHub Actions **variables** (not secrets; they're ARNs):

| Variable | Value |
|---|---|
| `AWS_REGION` | e.g. `us-east-1` |
| `AWS_PLAN_ROLE_ARN` | bootstrap output `terraform_plan_role_arn` |
| `AWS_IMAGE_PUSH_ROLE_ARN` | dev output `ci_image_push_role_arn` |
| `AWS_APPLY_ROLE_ARN` (on the `dev` Environment) | bootstrap output `terraform_apply_role_arn` |

Protect the `dev` Environment with required reviewers.

## 6. Ship the sample app

1. Create its secret, which is optional (the app falls back to a default greeting):
   ```bash
   aws secretsmanager create-secret --name tf-eks-infra-dev/sample-app \
     --secret-string '{"GREETING":"hello from Secrets Manager"}'
   ```
2. Push a change under `app/sample/`. The `image` workflow builds, scans, pushes, signs and attests the image, then opens a PR that pins the new digest in `workloads/sample/overlays/eks/kustomization.yaml`.
3. Merge it. Argo CD deploys, and Kyverno verifies the signature at admission.

## 7. Prove the controls work

```bash
# Unsigned / unpinned image: rejected
kubectl -n app-sample run test --image=nginx:latest
# LoadBalancer Service in a tenant namespace: rejected
kubectl -n app-sample create service loadbalancer test --tcp=80:80
# Namespace without PSA/tenant labels: rejected
kubectl create namespace team-x
# Debug containers with arbitrary images: rejected (ephemeral containers are covered too)
kubectl -n app-sample debug -it deploy/sample-app --image=busybox --target=app
# Falco -> Falcosidekick -> SNS: run Falco's event generator in a throwaway
# namespace (temporarily add it to systemNamespaces so policies allow it)
kubectl create ns falco-test && kubectl -n falco-test run eg \
  --image=falcosecurity/event-generator -- run syscall --loop
# Flows and policy verdicts
cilium hubble port-forward & hubble observe -n app-sample --verdict DROPPED
```
