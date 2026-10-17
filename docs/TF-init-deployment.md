# Initial deployment (Terraform)

These are the exact commands to stand up the AWS infrastructure from an empty account. Run them once per account and environment. For what happens after the cluster is up (GitOps, CI, the sample app), see [getting-started.md](getting-started.md).

> **Region:** everything below assumes `us-east-1`, the repo default. For another region, change `region` in `terraform/envs/dev/backend.tf` and pass `-var region=<region>` (or set `region` in `terraform.tfvars`) everywhere below.

> **Before step 4:** push this repo to GitHub. Argo CD pulls from `https://github.com/yicheung/tf-eks-infra.git`, and the platform apps stay at "repository not found" until it exists.

## 0. Prerequisites and AWS login

```bash
brew install terraform awscli kubectl        # Terraform must be >= 1.10 (S3-native state locking)
cd ~/Documents/GitHub/K8-infra/tf-eks-infra

aws configure sso                             # one-time, if you use IAM Identity Center
aws sso login --profile <your-admin-profile>
export AWS_PROFILE=<your-admin-profile>
aws sts get-caller-identity                   # confirm you're in the right account
```

## 1. Bootstrap: state bucket, KMS key, GitHub OIDC, CI roles

```bash
cd terraform/bootstrap
terraform init
terraform plan -out=tfplan \
  -var region=us-east-1 \
  -var github_repository=yicheung/tf-eks-infra
terraform apply tfplan
```

**If the account already has a GitHub OIDC provider**, the apply fails with `EntityAlreadyExists`. Import the existing one, then re-run the plan and apply:

```bash
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com
```

What this creates:

| Resource | Purpose |
|---|---|
| S3 bucket `tf-eks-infra-tfstate-<account>-<region>` | Terraform state: versioned, SSE-KMS, TLS-only, public access blocked, `prevent_destroy` |
| KMS key `alias/tf-eks-infra-tfstate` | Encrypts state |
| GitHub OIDC provider | Lets GitHub Actions get short-lived AWS credentials |
| `tf-eks-infra-terraform-plan` role | Read-only. Assumable from PRs and `main` |
| `tf-eks-infra-terraform-apply` role | Assumable only from the protected `dev` GitHub Environment |

## 2. Move bootstrap's state into the bucket it just created

```bash
BUCKET=$(terraform output -raw state_bucket_name)

cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket       = "$BUCKET"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
EOF

terraform init -migrate-state                 # answer "yes"
```

Leave the commented-out backend block in `versions.tf` as it is. Terraform allows only one backend block, and `backend.tf` is now it. Commit `backend.tf`. After migration, the local `terraform.tfstate*` files are git-ignored, and you can delete them once you've confirmed the state is in S3:

```bash
aws s3 ls "s3://$BUCKET/bootstrap/"
```

## 3. Configure the dev environment

```bash
cd ../envs/dev
sed -i '' "s/REPLACE_WITH_state_bucket_name/$BUCKET/" backend.tf
cp terraform.tfvars.example terraform.tfvars
```

These commands print the values for `terraform.tfvars`:

```bash
# github_oidc_provider_arn
terraform -chdir=../../bootstrap output -raw github_oidc_provider_arn

# cluster_admin_principal_arns: the CI apply role...
terraform -chdir=../../bootstrap output -raw terraform_apply_role_arn
# ...and your SSO admin role (the IAM role ARN, not the assumed-role ARN)
aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/ \
  --query 'Roles[?contains(RoleName, `Admin`)].Arn' --output text

# api_public_access_cidrs: your current egress IP
echo "$(curl -s https://checkip.amazonaws.com)/32"
```

A finished `terraform.tfvars` looks like this:

```hcl
region                   = "us-east-1"
github_repository        = "yicheung/tf-eks-infra"
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
api_public_access_cidrs  = ["203.0.113.10/32"]

cluster_admin_principal_arns = [
  "arn:aws:iam::123456789012:role/tf-eks-infra-terraform-apply",
  "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_abc123",
]

security_alert_emails = ["you@example.com"]
platform_alert_emails = ["you@example.com"]   # Alertmanager (operational) alerts
```

> **Don't skip this:** `cluster_admin_principal_arns` must include the role you're running Terraform as. There's no automatic creator-admin, so leaving it out locks Terraform out of the cluster it just created. Use the IAM role ARN (`arn:aws:iam::…:role/aws-reserved/…`), not the `arn:aws:sts::…:assumed-role/…` ARN that `get-caller-identity` prints.

`terraform.tfvars` holds no secrets (ARNs, CIDRs), so commit it so CI can plan.

## 4. Apply in two passes

On the first run the Helm provider has no cluster to connect to yet, so create the network and cluster first, then everything else:

```bash
terraform init
terraform apply -target=module.network -target=module.eks    # ~15-20 min
terraform apply                                               # ~10-15 min
```

| Pass | Creates |
|---|---|
| 1 | VPC, subnets, NAT, VPC endpoints, flow logs; EKS control plane, KMS secrets encryption, control-plane logs, access entries, Pod Identity agent, Bottlerocket node group |
| 2 | Gateway API CRDs, Cilium, CoreDNS; Pod Identity roles; ECR + CI push role; GuardDuty, SNS alerts, CloudWatch Observability; EBS CSI driver + KMS key; platform-alerts SNS + Alertmanager role; Argo CD + root Application |

Expected along the way:
- Terraform warns that `-target` gives a partial apply. Pass 2 completes it.
- Nodes are `NotReady` between passes, because there's no CNI until Cilium is installed in pass 2.

Later applies are a single `terraform apply`.

## 5. Verify

```bash
$(terraform output -raw kubeconfig_command)

kubectl get nodes                                    # all Ready
kubectl -n kube-system get pods -l k8s-app=cilium    # Running on every node
kubectl -n kube-system get pods -l k8s-app=kube-dns  # CoreDNS Running
kubectl -n argocd get applications -w                # all apps reach Synced / Healthy
```

Argo CD UI:

```bash
$(terraform output -raw argocd_ui_command)           # then open https://localhost:8080
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo   # user: admin
```

Grafana, Prometheus and Alertmanager (details in [monitoring.md](monitoring.md)):

```bash
$(terraform output -raw grafana_ui_command)          # then open http://localhost:3000
kubectl -n monitoring get secret grafana-admin \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo   # user: admin
```

Confirm the SNS subscription emails that `security_alert_emails` and `platform_alert_emails` receive. Alerts aren't delivered until you do.

## 6. Hand over to CI

Set these in the GitHub repo under **Settings -> Secrets and variables -> Actions -> Variables**:

| Variable | Scope | Value |
|---|---|---|
| `AWS_REGION` | repository | `us-east-1` |
| `AWS_PLAN_ROLE_ARN` | repository | `terraform -chdir=terraform/bootstrap output -raw terraform_plan_role_arn` |
| `AWS_IMAGE_PUSH_ROLE_ARN` | repository | `terraform -chdir=terraform/envs/dev output -raw ci_image_push_role_arn` |
| `AWS_APPLY_ROLE_ARN` | `dev` Environment | `terraform -chdir=terraform/bootstrap output -raw terraform_apply_role_arn` |

Create the `dev` Environment under **Settings -> Environments** and add required reviewers. From then on, `terraform apply` runs from CI on merge to `main`.

> **API access from CI:** GitHub-hosted runners have changing IPs, so they can't reach an API endpoint restricted to `api_public_access_cidrs`. Use a self-hosted runner inside the VPC, or a runner with a static egress IP added to that list. See *Known gaps* in [security-controls.md](security-controls.md#known-gaps).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `EntityAlreadyExists` on the OIDC provider (step 1) | Import it (step 1). |
| `Unauthorized` / `the server has asked for the client to provide credentials` in pass 2 | The identity running Terraform isn't in `cluster_admin_principal_arns`. Add the IAM role ARN and re-apply. |
| `context deadline exceeded` / can't reach the cluster | Your IP changed or isn't in `api_public_access_cidrs`. Update it and run `terraform apply -target=module.eks`. |
| `helm_release.cilium` times out | Check `kubectl -n kube-system describe pod -l app.kubernetes.io/name=cilium-operator`. ENI permissions come from the `cilium-operator` Pod Identity role. |
| `aws_eks_addon.coredns` stuck `DEGRADED` | Cilium isn't Ready on the nodes yet. Check `kubectl -n kube-system get pods -l k8s-app=cilium`. |
| Argo CD apps `Unknown` / repo not found | The repo isn't pushed to GitHub yet, or it's private and Argo CD needs repo credentials. |
| GuardDuty detector already exists | Set `create_guardduty_detector = false` and `existing_guardduty_detector_id = "<id>"` in `terraform.tfvars`. |

## Cost and teardown

While running, expect roughly **$10-15/day** (plus about $0.20/day for the monitoring volumes): EKS control plane, a NAT gateway, interface endpoints in 3 AZs, 2x `m7i.large`, GuardDuty and Inspector.

```bash
cd terraform/envs/dev
terraform destroy
```

The bootstrap state bucket has `prevent_destroy` set, on purpose. Leave it in place, or remove the lifecycle block deliberately if you're closing the account down.
