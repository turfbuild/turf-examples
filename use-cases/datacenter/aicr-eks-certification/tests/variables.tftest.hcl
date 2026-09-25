# The typed surface that replaced the config YAML: the AICR aws-h100 lane plans
# through the whole graph, and each validation rejects the input it exists for.

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
  # admin_roles by name are resolved to ARNs through data.aws_iam_role.
  mock_data "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Admin_0123456789abcdef"
    }
  }
}
mock_provider "http" {}
mock_provider "tls" {}
mock_provider "kubernetes" {}
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

run "aicr_h100_lane_plans" {
  command = plan

  # Defaults are upstream's try() fallbacks.
  assert {
    condition = (
      var.network.host_cidr == "10.0.0.0/16" && var.cluster.service_cidr == "172.20.0.0/16" &&
      var.autoscaling.instance_refresh.min_healthy_percentage == 90 && var.security.kms_deletion_window_days == 30 &&
      var.worker_pools["gpu-worker"].block_device.mount == "/dev/sda1" && var.worker_pools["gpu-worker"].architecture == "x86_64"
    )
    error_message = "optional() defaults must equal upstream's try() defaults"
  }

  # p5 → h100: all network cards EFA, and the default dedicated taint precedes
  # the pool's own.
  assert {
    condition     = module.eks_compute.worker_pools["gpu-worker"].gpu_family == "h100"
    error_message = "p5.48xlarge must derive gpu_family=h100"
  }

  assert {
    condition     = module.eks_compute.worker_pools["gpu-worker"].taints == "dedicated=worker-workload:NoSchedule,dedicated=worker-workload:NoExecute,skyhook.nvidia.com=runtime-required:NoSchedule"
    error_message = "GPU pools carry the dedicated taints plus their own"
  }

  # ENIConfigs for the system zones and the worker zone.
  assert {
    condition     = keys(module.eks_cluster.eni_configs) == tolist(["us-east-1a", "us-east-1c", "us-east-1e"])
    error_message = "one ENIConfig per system/worker zone"
  }
}

run "rejects_empty_reservation_target" {
  command = plan

  # AICR's GB200 lane (cluster-config-gb200.yaml) commits target: "".
  variables {
    worker_pools = {
      gpu-worker = {
        instance_type = "p6e-gb200.36xlarge"
        architecture  = "arm64"
        accelerator   = "gb200"
        capacity = {
          desired     = 2
          reservation = { preference = "capacity-reservations-only", target = "", market_type = "capacity-block" }
        }
      }
    }
  }

  expect_failures = [var.worker_pools]
}

run "rejects_more_private_than_public_subnets" {
  command = plan

  variables {
    network = {
      subnets = {
        public = [{ cidr = "10.0.1.0/27", zone = "us-east-1a" }]
        system = [{ cidr = "10.0.4.0/22", zone = "us-east-1a" }, { cidr = "10.0.8.0/22", zone = "us-east-1c" }]
        worker = [{ cidr = "10.0.128.0/17", zone = "us-east-1e" }]
      }
    }
  }

  expect_failures = [var.network]
}

run "rejects_long_deployment_id" {
  command = plan

  variables {
    deployment = {
      id       = "aicr-uat-day-ah1-0-12345678901234567890123"
      tenancy  = "123456789012"
      location = "us-east-1"
    }
  }

  expect_failures = [var.deployment]
}

run "rejects_unknown_taint_effect" {
  command = plan

  variables {
    system_pool = {
      instance_type = "m7i.xlarge"
      capacity      = { desired = 3 }
      taints        = [{ key = "dedicated", value = "x", effect = "NO_SCHEDULE" }]
    }
  }

  expect_failures = [var.system_pool]
}

run "rejects_inverted_capacity" {
  command = plan

  variables {
    worker_pools = {
      gpu-worker = {
        instance_type = "p5.48xlarge"
        capacity      = { desired = 4, max = 2 }
      }
    }
  }

  expect_failures = [var.worker_pools]
}

run "rejects_certifying_an_unknown_pool" {
  command = plan

  variables {
    certification = { pools = ["gpu-wroker"] }
  }

  expect_failures = [var.certification]
}

run "rejects_unpinned_version_shape" {
  command = plan

  variables {
    cluster = { version = "1.35.2" }
  }

  expect_failures = [var.cluster]
}
