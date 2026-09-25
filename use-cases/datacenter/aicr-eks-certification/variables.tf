# The typed surface that replaces mchmarny/cluster's config YAML.
#
# Upstream loaded one file with yamldecode(file(var.CONFIG_PATH)) and read every
# field through try(<path>, <default>). Here each section is a variable whose
# optional() defaults are those same <default>s, and the validation blocks below
# replace the JSON Schemas under upstream's schema/ (which were editor-only and
# had drifted from what the HCL reads). README.md has the full YAML → variable
# table.
#
# Dropped from the YAML, because each is something other than configuration:
#   deployment.provider   the module choice (this example is the EKS one)
#   deployment.state      the backend / Turf workspace binding
#   deployment.destroy    an engine verb: `turf destroy`, not a field
#   apiVersion, kind      nothing reads them
#
# One limit, measured on Terraform 1.16.2: an object-typed variable silently
# drops attributes it does not declare, so a misspelled key (instanceTyp) is
# ignored rather than rejected, exactly as try() ignored it. The types catch
# wrong types, missing required fields and out-of-range values; not typos.

variable "deployment" {
  description = "Deployment identity: id prefixes every resource name, tenancy is the AWS account, location the region."
  type = object({
    id       = string
    tenancy  = string
    location = string
    tags     = optional(map(string), {})
  })
  nullable = false

  validation {
    # IAM role names cap at 64 characters and the longest suffix appended here
    # is "-cloudwatch-observability" (25), so the id must stay at or under 39.
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}$", var.deployment.id))
    error_message = "deployment.id must be 1-39 characters of [a-z0-9-], starting with a letter; it prefixes IAM role names, which cap at 64."
  }
  validation {
    condition     = can(regex("^[0-9]{12}$", var.deployment.tenancy))
    error_message = "deployment.tenancy must be a 12-digit AWS account ID."
  }
  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.deployment.location))
    error_message = "deployment.location must be an AWS region, e.g. us-east-1."
  }
}

variable "cluster" {
  description = "EKS control plane. add_ons: null = not installed, \"\" = latest, \"vX.Y.Z-eksbuild.N\" = pinned."
  type = object({
    version       = string
    name          = optional(string) # null → deployment.id
    admin_roles   = optional(list(string), [])
    service_cidr  = optional(string, "172.20.0.0/16")
    allowed_cidrs = optional(list(string), [])
    add_ons = optional(object({
      core_dns                 = optional(string)
      vpc_cni                  = optional(string)
      kube_proxy               = optional(string)
      cloudwatch_observability = optional(string)
      metrics_server           = optional(string)
      ebs_csi                  = optional(string)
    }), {})
  })
  nullable = false

  validation {
    # Upstream treated the version as optional, but the Ubuntu AMI lookup
    # renders "ubuntu-eks/k8s_/images/*" without it, so it is required here.
    condition     = can(regex("^1\\.[0-9]+$", var.cluster.version))
    error_message = "cluster.version must be a Kubernetes minor version such as \"1.35\"."
  }
  validation {
    condition = alltrue([
      for v in values(var.cluster.add_ons) :
      v == null || can(regex("^(|v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+)$", v))
    ])
    error_message = "cluster.add_ons values must be null (not installed), \"\" (latest) or an EKS add-on version like v1.19.5-eksbuild.1."
  }
  validation {
    condition = alltrue([
      for r in var.cluster.admin_roles :
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", r)) || can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", r))
    ])
    error_message = "cluster.admin_roles entries must be an IAM role ARN or a bare role name."
  }
  validation {
    condition     = alltrue([for c in concat([var.cluster.service_cidr], var.cluster.allowed_cidrs) : can(cidrhost(c, 0))])
    error_message = "cluster.service_cidr and cluster.allowed_cidrs must be valid CIDR blocks."
  }
}

variable "network" {
  description = "VPC layout. subnets = null derives public /27, system /22 and worker /18 subnets in the first two AZs (pod /18s from pod_cidr)."
  type = object({
    host_cidr = optional(string, "10.0.0.0/16")
    pod_cidr  = optional(string, "100.65.0.0/16")
    subnets = optional(object({
      public = list(object({ cidr = string, zone = string }))
      system = list(object({ cidr = string, zone = string }))
      worker = list(object({ cidr = string, zone = string }))
      pod    = optional(list(object({ cidr = string, zone = string }))) # only with add_ons.vpc_cni
    }))
    endpoints = optional(list(string), ["s3", "ssm", "ec2messages", "ssmmessages", "logs"])
    additional_rules = optional(list(object({
      target      = string # system | worker | pod
      direction   = string # ingress | egress
      description = optional(string, "Custom rule")
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = optional(list(string), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(cidrhost(var.network.host_cidr, 0)) && can(cidrhost(var.network.pod_cidr, 0))
    error_message = "network.host_cidr and network.pod_cidr must be valid CIDR blocks."
  }
  validation {
    # Every private subnet routes through the NAT gateway with the same index in
    # the public list (upstream network.tf), so there must be at least as many
    # public subnets as system or worker subnets. Upstream failed at plan with an
    # invalid index; this says why.
    condition = var.network.subnets == null ? true : (
      length(var.network.subnets.system) <= length(var.network.subnets.public) &&
      length(var.network.subnets.worker) <= length(var.network.subnets.public)
    )
    error_message = "network.subnets needs at least as many public subnets as system or worker subnets: private subnet i routes through the NAT gateway in public subnet i."
  }
  validation {
    condition = var.network.subnets == null ? true : alltrue([
      for tier in [var.network.subnets.public, var.network.subnets.system, var.network.subnets.worker, coalesce(var.network.subnets.pod, [])] :
      length(distinct([for s in tier : s.zone])) == length(tier) && alltrue([for s in tier : can(cidrhost(s.cidr, 0))])
    ])
    error_message = "network.subnets: each tier may use a zone at most once, and every cidr must be valid."
  }
  validation {
    condition = alltrue([
      for r in var.network.additional_rules :
      contains(["system", "worker", "pod"], r.target) && contains(["ingress", "egress"], r.direction) &&
      alltrue([for c in r.cidr_blocks : can(cidrhost(c, 0))])
    ])
    error_message = "network.additional_rules: target must be system|worker|pod, direction ingress|egress, and cidr_blocks valid CIDRs."
  }
}

variable "ssh_public_key" {
  description = "Optional SSH public key for worker nodes."
  type        = string
  default     = null
}

variable "system_pool" {
  description = "The EKS managed node group for cluster-critical pods. Always tainted dedicated=system-workload; taints here are appended."
  type = object({
    instance_type = string
    capacity = object({
      desired = number
      min     = optional(number) # null → desired
      max     = optional(number) # null → desired
    })
    labels       = optional(map(string), {})
    taints       = optional(list(object({ key = string, value = string, effect = string })), [])
    block_device = optional(object({ size = optional(number, 50), type = optional(string, "gp3") }), {})
  })
  nullable = false

  validation {
    condition = (
      coalesce(var.system_pool.capacity.min, var.system_pool.capacity.desired) <= var.system_pool.capacity.desired &&
      var.system_pool.capacity.desired <= coalesce(var.system_pool.capacity.max, var.system_pool.capacity.desired)
    )
    error_message = "system_pool.capacity must satisfy min <= desired <= max."
  }
  validation {
    condition     = alltrue([for t in var.system_pool.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])
    error_message = "system_pool.taints effect must be NoSchedule, PreferNoSchedule or NoExecute."
  }
}

variable "worker_pools" {
  description = <<-EOT
    Self-managed worker pools (launch template + ASG), keyed by pool name.
    GPU pools (an accelerator set, or an instance family known to be GPU) get
    the dedicated=worker-workload taint and an EFA layout: gb200 and gb300 have
    dedicated layouts, other GPU families use every network card.
  EOT
  type = map(object({
    instance_type = string
    architecture  = optional(string, "x86_64")
    image_id      = optional(string) # null → most recent Canonical ubuntu-eks AMI (drifts; pin it)
    accelerator   = optional(string) # wins over instance-family derivation
    labels        = optional(map(string), {})
    taints        = optional(list(object({ key = string, value = string, effect = string })), [])
    block_device = optional(object({
      mount = optional(string, "/dev/sda1")
      size  = optional(number, 50)
      type  = optional(string, "gp3")
    }), {})
    capacity = object({
      desired = number
      min     = optional(number) # null → desired
      max     = optional(number) # null → desired
      reservation = optional(object({
        preference  = optional(string) # open | none | capacity-reservations-only
        target      = optional(string) # cr-… | resource-group ARN | resource-group name
        market_type = optional(string) # spot | capacity-block
      }))
    })
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.worker_pools) : can(regex("^[a-z0-9][a-z0-9-]*$", k))])
    error_message = "worker_pools keys must be [a-z0-9-]; they name the launch template and ASG."
  }
  validation {
    condition     = alltrue([for p in values(var.worker_pools) : contains(["x86_64", "arm64"], p.architecture)])
    error_message = "worker_pools[*].architecture must be x86_64 or arm64."
  }
  validation {
    condition     = alltrue([for p in values(var.worker_pools) : p.accelerator == null ? true : can(regex("^[a-z0-9]+$", p.accelerator))])
    error_message = "worker_pools[*].accelerator must be a lowercase GPU family such as h100, gb200 or gb300."
  }
  validation {
    condition = alltrue(flatten([
      for p in values(var.worker_pools) : [for t in p.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)]
    ]))
    error_message = "worker_pools[*].taints effect must be NoSchedule, PreferNoSchedule or NoExecute."
  }
  validation {
    condition = alltrue([
      for p in values(var.worker_pools) :
      coalesce(p.capacity.min, p.capacity.desired) <= p.capacity.desired &&
      p.capacity.desired <= coalesce(p.capacity.max, p.capacity.desired)
    ])
    error_message = "worker_pools[*].capacity must satisfy min <= desired <= max."
  }
  validation {
    condition = alltrue([
      for p in values(var.worker_pools) :
      try(p.capacity.reservation.preference, null) == null ? true :
      contains(["open", "none", "capacity-reservations-only"], p.capacity.reservation.preference)
    ])
    error_message = "worker_pools[*].capacity.reservation.preference must be open, none or capacity-reservations-only."
  }
  validation {
    condition = alltrue([
      for p in values(var.worker_pools) :
      try(p.capacity.reservation.market_type, null) == null ? true :
      contains(["spot", "capacity-block"], p.capacity.reservation.market_type)
    ])
    error_message = "worker_pools[*].capacity.reservation.market_type must be spot or capacity-block."
  }
  validation {
    # Upstream renders any non-null target, so "" became the ARN
    # "arn:aws:resource-groups:<region>:<account>:group/" — AICR's GB200 lane
    # carries exactly that value since its capacity block was retired.
    condition = alltrue([
      for p in values(var.worker_pools) :
      # A conditional, not coalesce(): coalesce() skips "" — the very value
      # this rule exists to reject.
      try(p.capacity.reservation.target, null) == null ? true : can(regex(
        "^(cr-[0-9a-f]{17}|arn:aws[a-z-]*:resource-groups:[a-z0-9-]+:[0-9]{12}:group/[A-Za-z0-9_.-]{1,128}|[A-Za-z0-9_.-]{1,128})$",
        p.capacity.reservation.target
      ))
    ])
    error_message = "worker_pools[*].capacity.reservation.target must be a capacity reservation ID (cr-…), a resource-group ARN or a resource-group name; not empty."
  }
}

variable "autoscaling" {
  description = "Worker ASG timeouts, health check and instance-refresh settings."
  type = object({
    capacity_timeout          = optional(string, "10m")
    delete_timeout            = optional(string, "30m")
    health_check_grace_period = optional(number, 300)
    instance_refresh = optional(object({
      min_healthy_percentage = optional(number, 90)
      instance_warmup        = optional(number, 300)
      checkpoint_percentages = optional(list(number), [50, 100])
    }), {})
  })
  default  = {}
  nullable = false
}

variable "iam" {
  description = "Extra managed-policy ARNs for the system and worker node roles."
  type = object({
    system_node_policies = optional(list(string), [])
    worker_node_policies = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in concat(var.iam.system_node_policies, var.iam.worker_node_policies) : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "iam.*_node_policies must be IAM policy ARNs."
  }
}

variable "observability" {
  description = "CloudWatch retention and ASG metrics granularity."
  type = object({
    log_retention_days          = optional(number, 7)
    vpc_flow_log_retention_days = optional(number, 7)
    metrics_granularity         = optional(string, "1Minute")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for d in [var.observability.log_retention_days, var.observability.vpc_flow_log_retention_days] :
      contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], d)
    ])
    error_message = "observability retention must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, …, 3653)."
  }
}

variable "security" {
  description = "KMS deletion window for the secrets-encryption key."
  type = object({
    kms_deletion_window_days = optional(number, 30)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.security.kms_deletion_window_days >= 7 && var.security.kms_deletion_window_days <= 30
    error_message = "security.kms_deletion_window_days must be between 7 and 30."
  }
}

variable "networking" {
  description = "VPC CNI warm-pool targets (used only with cluster.add_ons.vpc_cni)."
  type = object({
    vpc_cni_minimum_ip_target = optional(number, 30)
    vpc_cni_warm_ip_target    = optional(number, 20)
  })
  default  = {}
  nullable = false
}

# ---------------------------------------------------------------------------
# New surface: what upstream left to CI. See modules/certification and
# modules/cuj-train, and kubewait-action.md for the waits they declare.
# ---------------------------------------------------------------------------

variable "certification" {
  description = <<-EOT
    The NVCRE Certification run against the GPU pools. pools names the
    worker_pools whose nodes are certified; node_selector finds those nodes
    (AICR labels every GPU pool nodeGroup=gpu-worker). categories and options
    pass straight into the Certification spec, which NVCRE makes immutable, so
    any change here is a new certification (a replace, not an update).
  EOT
  type = object({
    pools         = list(string)
    node_selector = optional(map(string), { nodeGroup = "gpu-worker" })
    name          = optional(string, "gpu-pools")
    namespace     = optional(string, "nvcre-certification")
    categories = optional(list(object({
      domain  = string
      variant = string
      options = optional(map(any))
    })), [{ domain = "communication", variant = "nccl-all-reduce" }])
    # Spec-level CategoryOptions (nvcre.nvidia.com/v1alpha1), e.g.
    # { testScale = "full-scale", thresholds = { busBandwidthGBps = "value >= 300" } }
    options = optional(map(any), {})
    # The GPU pools are tainted, so the workload pods need matching tolerations;
    # NVCRE injects them for every taint listed here.
    taint_selectors = optional(list(object({
      key    = string
      value  = optional(string)
      effect = optional(string)
    })), [{ key = "dedicated", value = "worker-workload" }])
    gang_scheduler = optional(object({
      scheduler_name = string
      queue          = optional(string)
    }))
    gpus_per_node  = optional(number, 8)
    census_timeout = optional(string, "30m")
    wait_timeout   = optional(string, "60m")
    settle         = optional(string, "2m")
    drain_timeout  = optional(string, "10m")
  })
  nullable = false

  validation {
    condition     = length(var.certification.pools) > 0 && alltrue([for p in var.certification.pools : contains(keys(var.worker_pools), p)])
    error_message = "certification.pools must name at least one key of worker_pools."
  }
  validation {
    condition     = length(var.certification.categories) >= 1 && length(var.certification.categories) <= 64
    error_message = "certification.categories must hold 1-64 entries (the Certification CRD's bounds)."
  }
  validation {
    condition = alltrue([
      for d in [var.certification.census_timeout, var.certification.wait_timeout, var.certification.settle, var.certification.drain_timeout] :
      can(regex("^([0-9]+(h|m|s))+$", d))
    ])
    error_message = "certification timeouts must be durations like 30m, 1h or 90s."
  }
}

variable "cuj_train" {
  description = "The training smoke run after certification passes. Defaults are AICR UAT's phase_train (tests/uat/lib/phases.sh)."
  type = object({
    enabled       = optional(bool, true)
    name          = optional(string, "pytorch-mnist")
    namespace     = optional(string, "kubeflow")
    num_nodes     = optional(number, 2)
    gpus_per_node = optional(number, 1)
    image         = optional(string, "kubeflow/pytorch-dist-mnist:v1-9e12c68")
    runtime       = optional(string, "torch-distributed")
    timeout       = optional(string, "20m")
  })
  default  = {}
  nullable = false
}
