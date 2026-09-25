# Ported from github.com/mchmarny/cluster provider/eks/terraform/main.tf @ 0ac8457
# (MIT, Copyright (c) 2025 Mark Chmarny; see LICENSE in this directory).
# Changes: the worker instance-type and Ubuntu AMI lookups moved to ../eks-compute,
#   the only module that reads them.

data "aws_caller_identity" "current" {}

# Query available AZs for default subnet generation
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# The runner's own egress IP is appended to the control plane's public-access
# CIDRs on every plan, so whoever runs the plan can reach the API server. Kept
# from upstream; it churns public_access_cidrs whenever the runner moves.
data "http" "egress_ip" {
  url             = "https://checkip.amazonaws.com"
  request_headers = { Accept = "text/plain" }
}
