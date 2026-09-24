# Ported from github.com/mchmarny/cluster provider/eks/terraform/main.tf @ 0ac8457
# (MIT, Copyright (c) 2025 Mark Chmarny; see LICENSE in this directory).
# Changes: moved here from the root module (compute is the only reader); config
#   lookups -> typed variables; the asg_* and metrics locals read var.autoscaling.

locals {
  prefix         = var.prefix
  region         = var.region
  effective_tags = var.tags

  // ASG Configuration
  asg_health_check_grace_period = var.autoscaling.health_check_grace_period
  asg_capacity_timeout          = var.autoscaling.capacity_timeout
  asg_delete_timeout            = var.autoscaling.delete_timeout
  asg_min_healthy_percentage    = var.autoscaling.instance_refresh.min_healthy_percentage
  asg_instance_warmup           = var.autoscaling.instance_refresh.instance_warmup
  asg_checkpoint_percentages    = var.autoscaling.instance_refresh.checkpoint_percentages

  metrics_granularity = var.metrics_granularity

  // EKS version for AMI lookup (must be specified for Ubuntu AMI auto-selection)
  eks_version_for_ami = var.cluster.version
}

# Instance type metadata for worker nodes (used to determine EFA network card count)
data "aws_ec2_instance_type" "worker" {
  for_each = {
    for name, pool in var.worker_pools : name => pool.instance_type
  }
  instance_type = each.value
}

# Ubuntu EKS Worker AMI lookup (used when image_id is not specified)
# https://cloud-images.ubuntu.com/docs/aws/eks/
# Only looks up architectures that are actually needed by node groups.
# most_recent = true drifts: AICR pins image_id per pool because this lookup
# moved its nodes to a new Ubuntu release mid-cycle (see the example README).
locals {
  needed_architectures = toset([
    for ng in local.worker_node_groups :
    ng.architecture
    if ng.image_id == null
  ])
}

data "aws_ami" "ubuntu_eks" {
  for_each = local.needed_architectures

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu-eks/k8s_${local.eks_version_for_ami}/images/*"]
  }

  filter {
    name   = "architecture"
    values = [each.value]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
