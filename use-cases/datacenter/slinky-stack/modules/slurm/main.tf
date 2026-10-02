# A Slurm cluster, as Slinky custom resources.
#
# This release renders no Pods, Deployments or StatefulSets of its own — only a
# Controller, a RestApi, a LoginSet, one NodeSet per entry in `nodesets`, and
# the Secrets and ConfigMaps they reference. The operator turns those into
# slurmctld, slurmrestd, sackd/sshd and slurmd pods. Two consequences:
#
#   - It needs the operator first, and not only for reconciliation: the
#     operator's validating webhook fails closed, so these objects are rejected
#     until it serves. The caller orders this module after it with depends_on.
#
#   - Helm's wait covers nothing that matters. Helm waits on the workloads in
#     its manifest, and there are none: the release reports deployed while
#     slurmctld is still pulling its image. The wait that does mean something is
#     an action on the release (below), on what Slurm itself reports.
#
# Everything Run:ai's tutorial does to the cluster after `helm install` — the
# GPU NodeSet it submits with `runai workload submit`, and the gres.conf
# ConfigMap and Controller patch it applies with kubectl — is in the values
# below, so a later upgrade cannot quietly undo it.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubewait = {
      source  = "turfbuild/kubewait"
      version = "~> 0.1"
    }
  }
}

variable "release_name" {
  description = <<-EOT
    Helm release name. Every object name derives from it: the Controller is
    <name>, NodeSets are <name>-worker-<key>, the LoginSet is <name>-login-<key>.
    "slurm" reproduces the tutorial's names.
  EOT
  type        = string
  default     = "slurm"
}

variable "namespace" {
  description = "Namespace for the Slurm cluster — the tutorial's Run:ai project namespace"
  type        = string
  default     = "slurm"
}

variable "chart_version" {
  description = "slurm chart version; keep it equal to the operator's"
  type        = string
  default     = "1.2.2"
}

variable "cpu_nodeset_replicas" {
  description = <<-EOT
    slurmd pods in the CPU NodeSet (chart key "slinky", as in the tutorial). The
    operator allows one slurmd per Kubernetes node, across all NodeSets, so this
    cannot usefully exceed the number of schedulable nodes.
  EOT
  type        = number
  default     = 1
}

variable "gpu_nodeset" {
  description = <<-EOT
    The GPU NodeSet (chart key "gpu", so NodeSet slurm-worker-gpu — the
    tutorial's name). Each slurmd pod requests gpus_per_node of nvidia.com/gpu,
    which is how Slurm and Kubernetes agree on what the node holds. null for no
    GPU NodeSet.
  EOT
  type = object({
    replicas      = number
    gpus_per_node = number
  })
  default = {
    replicas      = 1
    gpus_per_node = 4
  }
}

variable "scheduler" {
  description = <<-EOT
    A secondary scheduler for every Slurm pod: its schedulerName, and the label
    key and value that name the pod's queue. null leaves the default scheduler.
  EOT
  type = object({
    name        = string
    queue_label = string
    queue       = string
  })
  default = null
}

variable "non_preemptible" {
  description = <<-EOT
    Run every Slurm pod at Slinky's own slurm-system-critical priority. A queue
    scheduler treats a pod this important as non-preemptible, so it is admitted
    only within its queue's quota — Run:ai's default for a NodeSet ("very high
    priority, non-preemptible"). A Slurm node evicted by Kubernetes takes its
    running jobs with it.
  EOT
  type        = bool
  default     = true
}

variable "dcgm_job_mapping_dir" {
  description = <<-EOT
    Turn on the chart's NVIDIA DCGM hook: a prolog/epilog pair on GPU NodeSets
    that writes, per GPU, the ID of the Slurm job holding it into this host
    directory, where DCGM exporter reads it. Must equal the GPU Operator's
    dcgmExporter.hpcJobMapping.directory. null for off.
  EOT
  type        = string
  default     = null
}

variable "root_ssh_authorized_keys" {
  description = "Public keys for root on the login pod (the tutorial's --set-file); null for kubectl exec only"
  type        = string
  default     = null
}

variable "login_service_type" {
  description = <<-EOT
    Service type for the login pod's sshd. The chart defaults to LoadBalancer,
    which stays <pending> forever on kind; ClusterIP plus a port-forward works
    everywhere.
  EOT
  type        = string
  default     = "ClusterIP"
}

variable "timeout" {
  description = "Seconds helm may take to install or upgrade the release"
  type        = number
  default     = 600
}

variable "ready_timeout" {
  description = "How long the CPU partition may take to report every node IDLE before the apply fails"
  type        = string
  default     = "15m"
}

variable "cluster_endpoint" {
  description = "API endpoint of the containing cluster — see the gpu-operator module for why"
  type        = string
}

resource "terraform_data" "cluster" {
  triggers_replace = var.cluster_endpoint
}

locals {
  # Merged into every pod-bearing object below. The label goes on the custom
  # resource *and* its pod template — the chart puts `metadata` on both — so the
  # queue is found whether the scheduler looks at the pod or its top owner.
  #
  # (A splat over the nullable variable, merged, rather than `x == null ? {} :
  # {...}`: the two arms of a conditional must have one type, and an empty
  # object and this one do not.)
  scheduled = merge([for s in var.scheduler[*] : {
    metadata = { labels = { (s.queue_label) = s.queue } }
    podSpec  = { schedulerName = s.name }
  }]...)

  gpu_nodesets = { for g in var.gpu_nodeset[*] : "gpu" => {
    replicas = g.replicas
    slurmd = {
      resources = { limits = { "nvidia.com/gpu" = g.gpus_per_node } }
    }
    # GPU node pools are commonly tainted so that only GPU work lands there.
    podSpec = {
      tolerations = [{ key = "nvidia.com/gpu", operator = "Exists", effect = "NoSchedule" }]
    }
  } }

  values = {
    # Step 7 of the tutorial, as values. AutoDetect=nvidia needs no NVML library
    # in the slurmd image (it reads /proc and /dev), and GresTypes must be set
    # explicitly: Slurm manages no generic resources by default.
    configFiles = { "gres.conf" = "AutoDetect=nvidia" }
    controller  = merge(local.scheduled, { extraConfMap = { GresTypes = ["gpu"] } })
    restapi     = local.scheduled

    priorityClass = { enabled = var.non_preemptible, create = var.non_preemptible }

    loginsets = {
      slinky = merge(local.scheduled, {
        rootSshAuthorizedKeys = var.root_ssh_authorized_keys
        service               = { spec = { type = var.login_service_type } }
      })
    }

    nodesetDefaults = local.scheduled
    nodesets = merge(
      { slinky = { replicas = var.cpu_nodeset_replicas } },
      local.gpu_nodesets,
    )
    partitions = { all = { enabled = true } }

    vendor = {
      nvidia = {
        dcgm = merge(
          { enabled = var.dcgm_job_mapping_dir != null },
          var.dcgm_job_mapping_dir == null ? {} : { jobMappingDir = var.dcgm_job_mapping_dir },
        )
      }
    }
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "oci://ghcr.io/slinkyproject/charts"
  chart      = "slurm"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  values = [yamlencode(local.values)]

  # Off, because there is nothing for it to wait on (see the top of this file).
  # The action triggers below are the wait.
  wait    = false
  timeout = var.timeout

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]

    # Hook: the apply is not done until Slurm says the CPU partition is up.
    # taint: a cluster that never came up is reinstalled by the next `up`
    # rather than left in state looking finished.
    action_trigger {
      events     = [after_create]
      actions    = [action.kubewait_condition.cpu_nodes_up]
      on_failure = taint
    }

    # The same check after a change to the values, such as a replica count.
    action_trigger {
      events  = [after_update]
      actions = [action.kubewait_condition.cpu_nodes_up]
    }

    # Confirmation: the release is not gone until its pods are. helm uninstall
    # deletes the custom resources and returns at once; it is the operator that
    # then tears the pods down. The operator's module depends on this one, so
    # holding this destroy keeps the operator alive until it has finished.
    action_trigger {
      events  = [after_destroy]
      actions = [action.kubewait_condition.slurm_pods_drained]
    }
  }
}

# The CPU partition, as Slurm sees it.
#
# The NodeSet's status is the operator's report of Slurm's own view: how many of
# its pods are registered with slurmctld as IDLE, ALLOCATED, DOWN or DRAIN.
# Pods being Ready is not the same thing — a slurmd can be running and still be
# DOWN to the controller. So this passes only when every replica is Ready and
# every one is a usable Slurm node (IDLE, or ALLOCATED if a job got there
# first), with none DOWN.
#
# has(object.status) first: a NodeSet has no status at all until the operator
# can reach slurmctld, and has() on a field of a missing map is an error, not
# false. kubewait holds an error at pending, so the verdict is the same either
# way; without the guard, the progress just says "CEL error" for the first
# few minutes.
action "kubewait_condition" "cpu_nodes_up" {
  config {
    api_version     = "slinky.slurm.net/v1beta1"
    kind            = "NodeSet"
    namespace       = var.namespace
    name            = "${var.release_name}-worker-slinky"
    expression      = <<-CEL
      has(object.status) && has(object.status.readyReplicas) &&
      object.status.readyReplicas == ${var.cpu_nodeset_replicas} &&
      (has(object.status.slurmIdle) ? object.status.slurmIdle : 0) +
      (has(object.status.slurmAllocated) ? object.status.slurmAllocated : 0) == ${var.cpu_nodeset_replicas} &&
      !(has(object.status.slurmDown) && object.status.slurmDown > 0)
    CEL
    timeout         = var.ready_timeout
    settle          = "10s"
    progress_fields = ["status.readyReplicas", "status.slurmIdle", "status.slurmAllocated", "status.slurmDown"]
  }
}

# The GPU partition, as Slurm sees it. Triggered by nothing: invoke it to ask
# (see the README). On a cluster with GPUs it passes as soon as the GPU
# NodeSet's nodes register. On kind it can only time out — the pods never
# schedule — and its progress shows the NodeSet stuck at zero Ready.
action "kubewait_condition" "gpu_nodes_up" {
  config {
    api_version     = "slinky.slurm.net/v1beta1"
    kind            = "NodeSet"
    namespace       = var.namespace
    name            = "${var.release_name}-worker-gpu"
    expression      = <<-CEL
      has(object.status) && has(object.status.slurmIdle) &&
      object.status.slurmIdle + (has(object.status.slurmAllocated) ? object.status.slurmAllocated : 0) == ${try(var.gpu_nodeset.replicas, 0)}
    CEL
    absent          = "failure"
    timeout         = "1m"
    progress_fields = ["status.replicas", "status.unavailableReplicas", "status.slurmIdle"]
  }
}

# Every pod in the Slurm namespace gone. The whole namespace rather than a
# label: only the slurmd pods carry slinky.slurm.net/cluster, and the
# controller, login and REST API pods are the ones that hold on longest.
# Destroy-time configuration, so it names nothing but variables.
action "kubewait_condition" "slurm_pods_drained" {
  config {
    api_version     = "v1"
    kind            = "Pod"
    namespace       = var.namespace
    min_matching    = 0
    max_matching    = 0
    timeout         = "5m"
    progress_fields = ["status.phase"]
  }
}

output "namespace" {
  description = "Namespace the Slurm cluster was installed into"
  value       = helm_release.this.namespace
}

output "chart_version" {
  description = "Chart version actually deployed"
  value       = helm_release.this.metadata.version
}

output "nodesets" {
  description = <<-EOT
    NodeSet name → the Slurm node names its pods register as. The chart sets
    each pod's hostname to "<key>-", so the ordinal follows the key, not the
    NodeSet name.
  EOT
  value = merge(
    { "${var.release_name}-worker-slinky" = [for i in range(var.cpu_nodeset_replicas) : "slinky-${i}"] },
    var.gpu_nodeset == null ? {} : {
      "${var.release_name}-worker-gpu" = [for i in range(var.gpu_nodeset.replicas) : "gpu-${i}"]
    },
  )
}

output "login_deployment" {
  description = "The login pod's Deployment, for kubectl exec"
  value       = "${var.release_name}-login-slinky"
}
