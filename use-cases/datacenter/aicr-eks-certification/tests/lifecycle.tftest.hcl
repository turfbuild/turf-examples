# The whole graph, applied and destroyed with every provider mocked. The
# kubewait actions are tfcoremock echoes here, so this proves the wiring, not
# the waits: every trigger (the census gate, the terminal hook, the TrainJob
# hook, and on teardown the after_destroy drains and the LoadBalancer gate) is
# planned and invoked in graph order, and the destroy walks the graph in
# reverse. The engine-level claims in README.md are not tested here.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1c", "us-east-1e"]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/mock" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::123456789012:instance-profile/mock" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/aicr-uat-1234567890"
      endpoint              = "https://aicr-uat-1234567890.example"
      certificate_authority = [{ data = "Y2E=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK" }] }]
    }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  # admin_roles by name are resolved to ARNs through data.aws_iam_role.
  mock_data "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Admin_0123456789abcdef"
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
mock_provider "kubernetes" {
  mock_resource "kubernetes_manifest" {
    defaults = {
      object = { metadata = { uid = "00000000-0000-0000-0000-000000000000" } }
    }
  }
  mock_data "kubernetes_nodes" {
    defaults = {
      nodes = [
        { metadata = [{ name = "ip-10-0-130-4.ec2.internal" }], spec = [{ provider_id = "aws:///us-east-1e/i-0aaaaaaaaaaaaaaaa" }] },
        { metadata = [{ name = "ip-10-0-200-7.ec2.internal" }], spec = [{ provider_id = "aws:///us-east-1e/i-0bbbbbbbbbbbbbbbb" }] },
      ]
    }
  }
}
mock_provider "helm" {}
mock_provider "kubewait" {}

override_data {
  target = module.eks_cluster.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
    arn        = "arn:aws:sts::123456789012:assumed-role/ci-deployer/session"
  }
}

override_data {
  target = module.eks_cluster.data.http.egress_ip
  values = {
    response_body = "203.0.113.10"
  }
}

# terraform.tfvars.example, inlined: AICR's aws-h100 lane with placeholder ids.
variables {
  deployment = {
    id       = "aicr-uat-1234567890"
    tenancy  = "123456789012"
    location = "us-east-1"
    tags     = { env = "dev" }
  }
  cluster = {
    version       = "1.35"
    admin_roles   = ["AWSReservedSSO_Admin_0123456789abcdef"]
    allowed_cidrs = ["203.0.113.0/30"]
    add_ons       = { core_dns = "", kube_proxy = "", vpc_cni = "" }
  }
  network = {
    subnets = {
      public = [{ cidr = "10.0.1.0/27", zone = "us-east-1a" }, { cidr = "10.0.2.0/27", zone = "us-east-1c" }]
      system = [{ cidr = "10.0.4.0/22", zone = "us-east-1a" }, { cidr = "10.0.8.0/22", zone = "us-east-1c" }]
      worker = [{ cidr = "10.0.128.0/17", zone = "us-east-1e" }]
      pod    = [{ cidr = "100.65.0.0/16", zone = "us-east-1e" }]
    }
  }
  system_pool = {
    instance_type = "m7i.xlarge"
    capacity      = { desired = 3 }
    labels        = { nodeGroup = "system-worker", dedicated = "system-workload" }
  }
  worker_pools = {
    gpu-worker = {
      instance_type = "p5.48xlarge"
      image_id      = "ami-0123456789abcdef0"
      capacity = {
        desired     = 2
        reservation = { preference = "capacity-reservations-only", target = "cr-0123456789abcdef0" }
      }
      labels = { nodeGroup = "gpu-worker", dedicated = "user-workload" }
      taints = [{ key = "skyhook.nvidia.com", value = "runtime-required", effect = "NoSchedule" }]
    }
  }
  certification = {
    pools          = ["gpu-worker"]
    gang_scheduler = { scheduler_name = "kai-scheduler" }
  }
}

run "whole_graph_applies" {
  command = apply

  assert {
    condition     = output.certification.node_names == tolist(["ip-10-0-130-4.ec2.internal", "ip-10-0-200-7.ec2.internal"])
    error_message = "the Certification targets the GPU nodes read after the stack settled"
  }

  assert {
    condition     = output.cuj_train.name == "pytorch-mnist" && output.cuj_train.namespace == "kubeflow"
    error_message = "the training smoke runs after certification, with AICR UAT's defaults"
  }
}

run "reapply_is_a_no_op_for_the_certificate" {
  command = apply

  assert {
    condition     = module.certification.identity == run.whole_graph_applies.certification_identity
    error_message = "re-applying unchanged inputs must not re-certify"
  }
}
