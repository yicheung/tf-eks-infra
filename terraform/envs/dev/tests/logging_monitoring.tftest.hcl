# Tests for the logging and monitoring switches. Plan-only with mocked
# providers, so they run without AWS credentials or a cluster:
#   terraform -chdir=terraform/envs/dev init -backend=false
#   terraform -chdir=terraform/envs/dev test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock"
    }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:123456789012:rule/mock"
    }
  }
  mock_resource "aws_security_group" {
    defaults = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0123456789abcdef0"
      id  = "sg-0123456789abcdef0"
    }
  }
  mock_resource "aws_launch_template" {
    defaults = {
      arn = "arn:aws:ec2:us-east-1:123456789012:launch-template/lt-0123456789abcdef0"
      id  = "lt-0123456789abcdef0"
    }
  }
  mock_resource "aws_eks_node_group" {
    defaults = {
      arn = "arn:aws:eks:us-east-1:123456789012:nodegroup/mock/mock/0"
    }
  }
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:123456789012:repository/mock"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/mock"
    }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/mock"
      endpoint              = "https://ABCDEF.gr7.us-east-1.eks.amazonaws.com"
      certificate_authority = [{ data = "dGVzdA==" }]
    }
  }
}

mock_provider "helm" {}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "null" {}
mock_provider "cloudinit" {}

variables {
  github_oidc_provider_arn     = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  api_public_access_cidrs      = ["198.51.100.10/32"]
  cluster_admin_principal_arns = ["arn:aws:iam::123456789012:user/test"]
}

run "defaults_enable_everything" {
  command = plan

  assert {
    condition     = length(module.storage) == 1 && length(module.monitoring) == 1
    error_message = "With defaults, the storage and monitoring modules must be created."
  }
  assert {
    condition     = output.grafana_ui_command != null
    error_message = "With defaults, the Grafana access command must be set."
  }
  assert {
    condition     = output.control_plane_log_group != null
    error_message = "With defaults, control-plane logging must be on."
  }
}

run "lean_dev_profile" {
  command = plan

  variables {
    enable_monitoring       = false
    enable_container_logs   = false
    enable_flow_logs        = false
    control_plane_log_types = ["audit", "authenticator"]
  }

  assert {
    condition     = length(module.storage) == 0 && length(module.monitoring) == 0
    error_message = "enable_monitoring = false must skip the storage and monitoring modules."
  }
  assert {
    condition     = output.platform_alerts_topic_arn == null && output.grafana_ui_command == null
    error_message = "enable_monitoring = false must not expose monitoring outputs."
  }
  assert {
    condition     = output.control_plane_log_group != null
    error_message = "audit + authenticator must still create the control-plane log group."
  }
}

run "control_plane_logging_off" {
  command = plan

  variables {
    control_plane_log_types = []
  }

  assert {
    condition     = output.control_plane_log_group == null
    error_message = "control_plane_log_types = [] must turn control-plane logging off."
  }
}

run "rejects_unknown_log_type" {
  command = plan

  variables {
    control_plane_log_types = ["audit", "everything"]
  }

  expect_failures = [var.control_plane_log_types]
}
