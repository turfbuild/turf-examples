# Ported from github.com/mchmarny/cluster provider/eks/terraform/tests/compute.tftest.hcl
# @ 0ac8457 (MIT, Copyright (c) 2025 Mark Chmarny). The assertions are upstream's,
# unchanged; tests/config.yaml became the variables block below, and the run
# targets modules/eks-compute, where compute.tf now lives.
#
# EFA network interface layout per GPU family (compute.tf locals)
# Run with: terraform test (providers are mocked — no AWS credentials needed)

mock_provider "aws" {}

variables {
  prefix     = "tftest"
  region     = "us-west-2"
  account_id = "123456789012"
  tags       = {}
  cluster = {
    name                       = "tftest"
    version                    = "1.35"
    endpoint                   = "https://tftest.example"
    certificate_authority_data = "Y2E="
    service_cidr               = "172.20.0.0/16"
  }
  subnet_ids_by_type          = { public = ["subnet-pub"], system = ["subnet-sys"], worker = ["subnet-wkr"], pod = [] }
  system_subnet_ids           = ["subnet-sys"]
  security_group_ids          = { efa = "sg-efa", worker = "sg-worker" }
  worker_instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/tftest-worker-nodes"
  system_node_role = {
    arn                = "arn:aws:iam::123456789012:role/tftest-system-nodes"
    policy_attachments = []
  }
  addon_role_arns = {
    cloudwatch_observability = "arn:aws:iam::123456789012:role/tftest-cloudwatch-observability"
    ebs_csi                  = "arn:aws:iam::123456789012:role/tftest-ebs-csi-driver"
  }
  ssh_public_key      = null
  metrics_granularity = "1Minute"
  add_ons             = { core_dns = null, cloudwatch_observability = null, metrics_server = null, ebs_csi = null }
  autoscaling = {
    capacity_timeout          = "10m"
    delete_timeout            = "30m"
    health_check_grace_period = 300
    instance_refresh          = { min_healthy_percentage = 90, instance_warmup = 300, checkpoint_percentages = [50, 100] }
  }
  system_pool = {
    instance_type = "m7i.xlarge"
    capacity      = { desired = 1, min = null, max = null }
    labels        = {}
    taints        = []
    block_device  = { size = 50, type = "gp3" }
  }
  worker_pools = {
    # GB200: gpu family must be derived from the instance type prefix
    gb200 = {
      instance_type = "p6e-gb200.36xlarge", architecture = "arm64", image_id = null, accelerator = null
      labels        = {}, taints = [], block_device = { mount = "/dev/sda1", size = 50, type = "gp3" }
      capacity      = { desired = 2, min = null, max = null, reservation = null }
    }
    # GB300: gpu family must be derived from the instance type prefix
    gb300 = {
      instance_type = "p6e-gb300r.36xlarge", architecture = "arm64", image_id = null, accelerator = null
      labels        = {}, taints = [], block_device = { mount = "/dev/sda1", size = 50, type = "gp3" }
      capacity      = { desired = 2, min = null, max = null, reservation = null }
    }
    # Explicit accelerator must win over prefix derivation
    accel = {
      instance_type = "x9z-unknown.48xlarge", architecture = "x86_64", image_id = null, accelerator = "gb200"
      labels        = {}, taints = [], block_device = { mount = "/dev/sda1", size = 50, type = "gp3" }
      capacity      = { desired = 1, min = null, max = null, reservation = null }
    }
    # Non-GPU worker: no EFA interfaces
    cpu = {
      instance_type = "m4.16xlarge", architecture = "x86_64", image_id = null, accelerator = null
      labels        = {}, taints = [], block_device = { mount = "/dev/sda1", size = 50, type = "gp3" }
      capacity      = { desired = 1, min = null, max = null, reservation = null }
    }
  }
}

run "gb200_family_derived_from_instance_type" {
  command = plan
  module {
    source = "./modules/eks-compute"
  }

  # GB200 (p6e-gb200.*) uses the AWS-recommended network card indices,
  # each card holding a single interface at device_index 0
  assert {
    condition = [
      for ni in aws_launch_template.node_groups["tftest-gb200"].network_interfaces :
      tonumber(ni.network_card_index)
    ] == [0, 1, 5, 9, 13]
    error_message = "p6e-gb200.36xlarge must derive gpu_family=gb200 and use network cards 0,1,5,9,13"
  }

  assert {
    condition = alltrue([
      for ni in aws_launch_template.node_groups["tftest-gb200"].network_interfaces :
      tonumber(ni.device_index) == 0
    ])
    error_message = "GB200 interfaces must all use device_index=0 (one interface per network card)"
  }

  assert {
    condition = [
      for ni in aws_launch_template.node_groups["tftest-gb200"].network_interfaces :
      ni.interface_type
    ] == ["interface", "efa-only", "efa-only", "efa-only", "efa-only"]
    error_message = "GB200 card 0 must be 'interface', remaining cards 'efa-only'"
  }
}

run "gb300_family_derived_from_instance_type" {
  command = plan
  module {
    source = "./modules/eks-compute"
  }

  # GB300 (p6e-gb300r.*) exposes only network card 0, so the layout is a single
  # EFA: a primary interface at device_index 0 plus one efa-only at device_index 1,
  # both on network_card_index 0.
  assert {
    condition = [
      for ni in aws_launch_template.node_groups["tftest-gb300"].network_interfaces :
      tonumber(ni.network_card_index)
    ] == [0, 0]
    error_message = "p6e-gb300r.36xlarge must derive gpu_family=gb300 and use only network card 0"
  }

  assert {
    condition = [
      for ni in aws_launch_template.node_groups["tftest-gb300"].network_interfaces :
      tonumber(ni.device_index)
    ] == [0, 1]
    error_message = "GB300 must place both interfaces on card 0 at device_index 0 and 1"
  }

  assert {
    condition = [
      for ni in aws_launch_template.node_groups["tftest-gb300"].network_interfaces :
      ni.interface_type
    ] == ["interface", "efa-only"]
    error_message = "GB300 card 0 must be a primary 'interface' plus one 'efa-only'"
  }
}

run "explicit_accelerator_overrides_derivation" {
  command = plan
  module {
    source = "./modules/eks-compute"
  }

  assert {
    condition = [
      for ni in aws_launch_template.node_groups["tftest-accel"].network_interfaces :
      tonumber(ni.network_card_index)
    ] == [0, 1, 5, 9, 13]
    error_message = "accelerator: gb200 must force the GB200 EFA layout regardless of instance type"
  }
}

run "non_gpu_worker_gets_no_efa_interfaces" {
  command = plan
  module {
    source = "./modules/eks-compute"
  }

  assert {
    condition     = length(aws_launch_template.node_groups["tftest-cpu"].network_interfaces) == 0
    error_message = "non-GPU workers must not declare EFA network interfaces"
  }
}

run "gpu_worker_gets_default_dedicated_taint" {
  command = plan
  module {
    source = "./modules/eks-compute"
  }

  # GPU pools keep the default dedicated=worker-workload taint
  assert {
    condition     = local.node_group_taints["gb300"] == "dedicated=worker-workload:NoSchedule,dedicated=worker-workload:NoExecute"
    error_message = "GPU worker pools must register the default dedicated=worker-workload taint"
  }
}

run "non_gpu_worker_is_untainted" {
  command = plan
  module {
    source = "./modules/eks-compute"
  }

  # Non-GPU (CPU) pools come out untainted: the taints string is empty,
  # rendering as `--register-with-taints=` in user-data, matching the GKE and
  # AKS providers.
  assert {
    condition     = local.node_group_taints["cpu"] == ""
    error_message = "non-GPU worker pools must be untainted (empty taints string)"
  }
}

# New: the post-compute add-ons wait for the node groups (README §Deviations 4).
run "deployment_addons_follow_node_groups" {
  command = plan
  module {
    source = "./modules/eks-compute"
  }

  variables {
    add_ons = { core_dns = "", cloudwatch_observability = null, metrics_server = "", ebs_csi = null }
  }

  assert {
    condition     = length(aws_eks_addon.coredns) == 1 && length(aws_eks_addon.metrics_server) == 1 && length(aws_eks_addon.ebs_csi_driver) == 0
    error_message = "add-ons are installed exactly when their version is non-null"
  }
}
