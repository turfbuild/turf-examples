# Ported from github.com/mchmarny/cluster provider/eks/terraform/main.tf @ 0ac8457
# (MIT, Copyright (c) 2025 Mark Chmarny; see LICENSE in this directory).
# Changes: every `try(local.config.<path>, <default>)` is now a typed variable
#   whose default is the same <default> (root variables.tf); compute-only locals
#   moved to ../eks-compute; the status-file path and config_* locals are gone.

locals {
  prefix      = var.deployment.id
  region      = var.deployment.location
  account     = var.deployment.tenancy // AWS account ID (consistent with other CSPs)
  egress_cidr = "${trimspace(data.http.egress_ip.response_body)}/32"

  eks_version  = var.cluster.version
  cluster_name = coalesce(var.cluster.name, local.prefix)

  // VPC CNI custom networking gate
  vpc_cni_enabled = var.cluster.add_ons.vpc_cni != null

  // Network
  vpc_cidr      = var.network.host_cidr
  pod_cidr      = var.network.pod_cidr
  service_cidr  = var.cluster.service_cidr
  vpc_endpoints = var.network.endpoints

  // Observability
  log_retention_days          = var.observability.log_retention_days
  vpc_flow_log_retention_days = var.observability.vpc_flow_log_retention_days

  // Security
  kms_deletion_window_days = var.security.kms_deletion_window_days

  // Use first 2 AZs for default subnets
  available_azs = slice(data.aws_availability_zones.available.names, 0,
  min(2, length(data.aws_availability_zones.available.names)))

  // Default subnets (auto-computed from VPC CIDR)
  default_subnets = {
    public = [for i, az in local.available_azs : {
      cidr = cidrsubnet(local.vpc_cidr, 11, i) # /27 (32 IPs)
      zone = az
    }]
    system = [for i, az in local.available_azs : {
      cidr = cidrsubnet(local.vpc_cidr, 6, i + 1) # /22 (1024 IPs)
      zone = az
    }]
    worker = [for i, az in local.available_azs : {
      cidr = cidrsubnet(local.vpc_cidr, 2, i + 2) # /18 (16384 IPs each)
      zone = az
    }]
    pod = [for i, az in local.available_azs : {
      cidr = cidrsubnet(local.pod_cidr, 2, i) # /18 from secondary CIDR
      zone = az
    }]
  }

  // Effective config: user subnets if provided, otherwise defaults. Pod subnets
  // exist only with VPC CNI custom networking.
  _user_subnets = var.network.subnets
  effective_subnets = {
    public = local._user_subnets != null ? local._user_subnets.public : local.default_subnets.public
    system = local._user_subnets != null ? local._user_subnets.system : local.default_subnets.system
    worker = local._user_subnets != null ? local._user_subnets.worker : local.default_subnets.worker
    pod = !local.vpc_cni_enabled ? [] : (
      try(local._user_subnets.pod, null) != null ? local._user_subnets.pod : local.default_subnets.pod
    )
  }
}
