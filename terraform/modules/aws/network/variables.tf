variable "name" {
  description = "Name prefix for the VPC and its resources."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. A /16 is expected: private subnets are carved as /19s so Cilium ENI prefix delegation has room for pods."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) == 16
    error_message = "vpc_cidr must be a valid /16."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 AZs. EKS needs at least 2."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, dev) instead of one per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints for ECR, STS, EKS Auth, logs, EC2, Secrets Manager and KMS. Each costs roughly $7-8/month per AZ."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch. Keep on outside throwaway dev clusters (CIS AWS 3.9)."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention for VPC flow logs."
  type        = number
  default     = 365
}

variable "log_kms_key_arn" {
  description = "KMS key ARN that encrypts the flow log group. The key policy must allow the CloudWatch Logs service principal."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
