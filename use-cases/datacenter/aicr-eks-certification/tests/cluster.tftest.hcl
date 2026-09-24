# Ported from github.com/mchmarny/cluster provider/eks/terraform/tests/cluster.tftest.hcl
# @ 0ac8457 (MIT, Copyright (c) 2025 Mark Chmarny). Upstream's assertions are
# unchanged; the fixture became the variables block and the run targets
# modules/eks-cluster. The ENIConfig runs below are new.
#
# EKS access entries for adminRoles (cluster.tf)
# bootstrap_cluster_creator_admin_permissions=true auto-creates an access entry
# for the deploying principal — an explicit entry for the same role 409s.
# Run with: terraform test (providers are mocked — no AWS credentials needed)

mock_provider "aws" {
  # Generated mock values are random strings; policy fields must be valid JSON
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  # A real region's AZ list, so default-subnet derivation has zones to use.
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-west-2a", "us-west-2b", "us-west-2c"]
    }
  }
  # The apply run below needs ARNs the aws provider's own validation accepts.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-west-2:123456789012:log-group:mock" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-west-2:123456789012:key/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/mock" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::123456789012:instance-profile/mock" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-west-2:123456789012:cluster/tftest"
      endpoint              = "https://tftest.example"
      certificate_authority = [{ data = "Y2E=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-west-2.amazonaws.com/id/MOCK" }] }]
    }
  }
}
mock_provider "http" {}
mock_provider "tls" {
  mock_data "tls_certificate" {
    defaults = {
      certificates = [{ sha1_fingerprint = "0000000000000000000000000000000000000000" }]
    }
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
    arn        = "arn:aws:sts::123456789012:assumed-role/AWSReservedSSO_CS-Admin_abc123/tester"
  }
}

override_data {
  target = data.http.egress_ip
  values = {
    response_body = "203.0.113.10"
  }
}

variables {
  deployment = { id = "tftest", tenancy = "123456789012", location = "us-west-2" }
  cluster = {
    version = "1.35"
    name    = null
    admin_roles = [
      # Same role the (mocked) caller deployed as — must be skipped (bootstrap
      # already grants the creator cluster-admin; explicit entry would 409)
      "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_CS-Admin_abc123",
      # Unrelated role — must still get an explicit access entry
      "arn:aws:iam::123456789012:role/other-admin",
    ]
    service_cidr  = "172.20.0.0/16"
    allowed_cidrs = []
    add_ons       = { core_dns = null, vpc_cni = null, kube_proxy = null, cloudwatch_observability = null, metrics_server = null, ebs_csi = null }
  }
  network = {
    host_cidr = "10.0.0.0/16"
    pod_cidr  = "100.65.0.0/16"
    subnets = {
      public = [{ cidr = "10.0.1.0/27", zone = "us-west-2a" }]
      system = [{ cidr = "10.0.4.0/22", zone = "us-west-2a" }]
      worker = [{ cidr = "10.0.128.0/17", zone = "us-west-2a" }]
      pod    = null
    }
    endpoints        = ["s3", "ssm", "ec2messages", "ssmmessages", "logs"]
    additional_rules = []
  }
  iam           = { system_node_policies = [], worker_node_policies = [] }
  observability = { log_retention_days = 7, vpc_flow_log_retention_days = 7 }
  security      = { kms_deletion_window_days = 30 }
}

run "creator_role_excluded_from_admin_access_entries" {
  command = plan
  module {
    source = "./modules/eks-cluster"
  }

  assert {
    condition     = length(aws_eks_access_entry.admin_roles) == 1
    error_message = "adminRoles entry matching the cluster creator must be skipped (EKS bootstrap already created it)"
  }

  assert {
    condition = contains(
      keys(aws_eks_access_entry.admin_roles),
      "arn:aws:iam::123456789012:role/other-admin"
    )
    error_message = "non-creator adminRoles must still get an explicit access entry"
  }

  assert {
    condition     = length(aws_eks_access_policy_association.admin_cluster_admin) == 1
    error_message = "policy associations must match the filtered access entries"
  }
}

# ENIConfigs exist only with VPC CNI custom networking (add_ons.vpc_cni set).
run "no_eni_configs_without_vpc_cni" {
  command = plan
  module {
    source = "./modules/eks-cluster"
  }

  assert {
    condition     = length(output.eni_configs) == 0
    error_message = "without cluster.add_ons.vpc_cni there must be no ENIConfigs"
  }
}

# One ENIConfig per zone, from the system and worker tiers. Upstream's template
# emitted system first and `kubectl apply` let the worker document overwrite a
# shared zone; the worker entry must win here too.
run "eni_configs_one_per_zone_worker_wins" {
  command = apply
  module {
    source = "./modules/eks-cluster"
  }

  variables {
    cluster = {
      version       = "1.35"
      name          = null
      admin_roles   = []
      service_cidr  = "172.20.0.0/16"
      allowed_cidrs = []
      add_ons       = { core_dns = null, vpc_cni = "", kube_proxy = null, cloudwatch_observability = null, metrics_server = null, ebs_csi = null }
    }
    network = {
      host_cidr = "10.0.0.0/16"
      pod_cidr  = "100.65.0.0/16"
      subnets = {
        public = [{ cidr = "10.0.1.0/27", zone = "us-west-2a" }, { cidr = "10.0.2.0/27", zone = "us-west-2b" }]
        system = [{ cidr = "10.0.4.0/22", zone = "us-west-2a" }, { cidr = "10.0.8.0/22", zone = "us-west-2b" }]
        worker = [{ cidr = "10.0.128.0/17", zone = "us-west-2b" }]
        pod    = [{ cidr = "100.65.0.0/16", zone = "us-west-2b" }]
      }
      endpoints        = ["s3"]
      additional_rules = []
    }
  }

  assert {
    condition     = keys(output.eni_configs) == tolist(["us-west-2a", "us-west-2b"])
    error_message = "one ENIConfig per zone across the system and worker tiers"
  }

  assert {
    condition     = output.eni_configs["us-west-2a"].subnet_id == aws_subnet.main["tftest-system-us-west-2a"].id
    error_message = "a system-only zone uses the system subnet"
  }

  assert {
    condition = (
      output.eni_configs["us-west-2b"].subnet_id == aws_subnet.main["tftest-worker-us-west-2b"].id &&
      output.eni_configs["us-west-2b"].security_group_id == aws_security_group.main["tftest-worker"].id
    )
    error_message = "a zone in both tiers takes the worker subnet and security group"
  }
}
