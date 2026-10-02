# KAI Scheduler — the scheduler inside NVIDIA Run:ai, open-sourced.
#
# Run:ai's tutorial puts Slurm in a Run:ai *project*: a namespace whose pods
# Run:ai schedules, against a queue with a GPU quota. This module is that
# arrangement with nothing proprietary in it:
#
#   Run:ai                              here
#   ------------------------------      ----------------------------------------
#   department                          Queue "datacenter" (parent)
#   project "slurm" + its GPU quota     Queue "slurm" (leaf), resources.gpu.quota
#   NodeSet as a native workload type   pod-grouper may read NodeSets (queues/)
#
# What it cannot reproduce is Run:ai taking a namespace over: KAI has no
# namespace-level scheduler injection, so each pod opts in itself with
# schedulerName plus a kai.scheduler/queue label. The caller sets both through
# the Slurm chart's values, from this module's outputs.

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
  description = "Helm release name"
  type        = string
  default     = "kai-scheduler"
}

variable "namespace" {
  description = <<-EOT
    Namespace KAI runs in; created if absent. Upstream's quickstart warns not to
    submit workloads here.
  EOT
  type        = string
  default     = "kai-scheduler"
}

variable "chart_version" {
  description = "kai-scheduler chart version (oci://ghcr.io/kai-scheduler/kai-scheduler)"
  type        = string
  default     = "v0.18.1"
}

variable "department" {
  description = "Parent queue — Run:ai's department"
  type        = string
  default     = "datacenter"
}

variable "project" {
  description = "Leaf queue pods are placed in — Run:ai's project"
  type        = string
  default     = "slurm"
}

variable "gpu_quota" {
  description = <<-EOT
    Whole GPUs the project queue is guaranteed. Run:ai's tutorial lists "project
    GPU quota sized for the NodeSet request" as a prerequisite: a non-preemptible
    workload is admitted only within quota.
  EOT
  type        = number
  default     = 0
}

variable "gpu_limit" {
  description = "Most GPUs the project queue may ever hold; -1 for no limit"
  type        = number
  default     = -1
}

variable "group_nodesets" {
  description = <<-EOT
    Let KAI's pod-grouper read Slinky NodeSets, so a NodeSet is scheduled as one
    PodGroup (as Run:ai lists it: one workload of type NodeSet) rather than one
    PodGroup per slurmd pod.
  EOT
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Seconds helm waits for each release to become Ready"
  type        = number
  default     = 600
}

variable "cluster_endpoint" {
  description = "API endpoint of the containing cluster — see the gpu-operator module for why"
  type        = string
}

resource "terraform_data" "cluster" {
  triggers_replace = var.cluster_endpoint
}

# The scheduler itself. It is operator-shaped: the chart installs kai-operator
# and a Config, and the operator then deploys the scheduler, binder,
# pod-grouper, admission webhook and queue controller. So helm's wait covers
# the operator and nothing it deploys — and the queue controller serves a
# validating webhook for Queue objects that fails closed. Measured: with helm's
# wait alone, the queues release below was refused ("failed calling webhook
# queue-validation.kai.scheduler ... connection refused"), 53 seconds before the
# operator reported the system ready.
#
# The action is the real wait: the operator's own verdict on its Config.
#
# The chart's own default queues stay on (they are harmless and match upstream's
# quickstart); this stack's pods never name them.
resource "helm_release" "this" {
  name       = var.release_name
  repository = "oci://ghcr.io/kai-scheduler/kai-scheduler"
  chart      = "kai-scheduler"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  wait    = true
  timeout = var.timeout

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]

    # Hook: nothing that depends on this release starts until KAI is ready.
    action_trigger {
      events     = [after_create]
      actions    = [action.kubewait_condition.kai_ready]
      on_failure = taint
    }
  }
}

# kai-operator's verdict on the components it deploys. Config is
# cluster-scoped, and the chart names it kai-config.
action "kubewait_condition" "kai_ready" {
  config {
    api_version        = "kai.scheduler/v1"
    kind               = "Config"
    name               = "kai-config"
    success_conditions = [{ type = "Ready", status = "True" }]
    timeout            = "10m"
    progress_fields    = ["status.conditions"]
  }
}

# The queues, and the pod-grouper's read access to NodeSets — see queues/.
#
# A local chart rather than resources of their own, so everything that writes to
# the cluster goes through helm. depends_on the release above for two things:
# the Queue CRD it installs (from the chart's crds/ directory, before any
# template), and — through its after_create hook — a queue controller that is
# serving the webhook every Queue must pass.
resource "helm_release" "queues" {
  name      = "${var.release_name}-queues"
  chart     = "${path.module}/queues"
  namespace = var.namespace

  values = [yamlencode({
    department = var.department
    project    = var.project
    gpu = {
      quota = var.gpu_quota
      limit = var.gpu_limit
    }
    podGrouper = {
      namespace      = var.namespace
      serviceAccount = "pod-grouper"
      readNodeSets   = var.group_nodesets
    }
  })]

  wait    = true
  timeout = var.timeout

  depends_on = [helm_release.this]

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]
  }
}

output "namespace" {
  description = "Namespace KAI was installed into"
  value       = helm_release.this.namespace
}

output "chart_version" {
  description = "Chart version actually deployed"
  value       = helm_release.this.metadata.version
}

output "scheduler_name" {
  description = "The schedulerName a pod sets to be placed by KAI"
  value       = "kai-scheduler"
}

output "queue" {
  description = <<-EOT
    The leaf queue pods name in their kai.scheduler/queue label. Read back from
    the values the queues release was installed with, so a caller that binds it
    is ordered after that release — and so after the scheduler, which the
    queues release itself waits for. No pod is created naming a queue that does
    not exist yet.
  EOT
  value       = yamldecode(helm_release.queues.values[0]).project
}

output "queue_label" {
  description = "The label key KAI reads a pod's (or its top owner's) queue from"
  value       = "kai.scheduler/queue"
}
