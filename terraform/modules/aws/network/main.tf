# Private-by-default VPC for EKS.
#   public  /24s  : internet-facing load balancers and NAT gateways only
#   private /19s  : worker nodes and pod ENIs (Cilium ENI mode)
#   intra   /24s  : EKS control-plane ENIs, no route to the internet
# Nodes never get public IPs. Outbound traffic leaves through NAT; AWS API
# traffic stays on VPC endpoints when enable_interface_endpoints = true.

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # 10.x.0.0/16 -> private /19s at 0,32,64; public /24s at .96+; intra /24s at .104+
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 3, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 96 + i)]
  intra_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 104 + i)]

  interface_endpoints = var.enable_interface_endpoints ? toset([
    "ecr.api", "ecr.dkr", "sts", "logs", "ec2", "eks", "eks-auth", "secretsmanager", "kms",
  ]) : toset([])
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  map_public_ip_on_launch = false
  enable_dns_hostnames    = true
  enable_dns_support      = true

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Lock the default SG down to no rules (CIS AWS 5.4).
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # VPC flow logs to CloudWatch, KMS-encrypted (toggle: enable_flow_logs).
  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = var.log_retention_days
  flow_log_cloudwatch_log_group_kms_key_id        = var.log_kms_key_arn

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# VPC endpoints: keep AWS API calls (ECR pulls, STS, Pod Identity, logs) off
# the internet path.
# ---------------------------------------------------------------------------
resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name_prefix = "${var.name}-vpce-"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpce" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.7"

  vpc_id = module.vpc.vpc_id

  endpoints = merge(
    {
      s3 = {
        service         = "s3"
        service_type    = "Gateway"
        route_table_ids = module.vpc.private_route_table_ids
        tags            = { Name = "${var.name}-s3" }
      }
    },
    {
      for svc in local.interface_endpoints : replace(svc, ".", "-") => {
        service             = svc
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.endpoints[0].id]
        tags                = { Name = "${var.name}-${svc}" }
      }
    }
  )

  tags = var.tags
}
