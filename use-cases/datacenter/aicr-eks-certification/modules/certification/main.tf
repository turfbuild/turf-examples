# An NVCRE Certification of the GPU pools, gated and awaited by actions.
#
# NVCRE (github.com/NVIDIA/cluster-readiness-engine, the chart pinned at v0.2.0
# by AICR's registry) turns one Certification into one Workflow per category,
# and each Workflow into Jobs and Kubeflow TrainJobs. AICR ADR-025 decision 6
# puts three duties on whoever creates the Certification, and this module maps
# each to an edge of the graph:
#
#   bound the footprint with target.nodeNames  → data.kubernetes_nodes below
#   treat expiry of its own wait as failure     → certification_terminal.timeout
#   confirm TrainJobs and pods are gone         → the after_destroy drains
#
# kubewait_condition is the generic wait action specified in
# ../../kubewait-action.md. It is not implemented; see the root versions.tf.

# Containment shim, the same pattern the generated bundle uses per component: a
# replaced cluster replaces what lived in the old one.
resource "terraform_data" "cluster" {
  triggers_replace = var.cluster_endpoint
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.settings.namespace
  }

  lifecycle {
    replace_triggered_by = [terraform_data.cluster]
  }
}

# The nodes to certify, read after the stack has settled (the root's
# module-level depends_on). Their names bound the Certification's footprint;
# their provider IDs (EC2 instance IDs) are part of what the certificate is of.
data "kubernetes_nodes" "gpu" {
  metadata {
    labels = var.settings.node_selector
  }
}

locals {
  node_names   = sort([for n in data.kubernetes_nodes.gpu.nodes : n.metadata[0].name])
  provider_ids = sort([for n in data.kubernetes_nodes.gpu.nodes : n.spec[0].provider_id])

  # nvcre.nvidia.com/v1alpha1 CertificationSpec: target, categories,
  # gangScheduler, and the inline CategoryOptions (var.settings.options).
  spec = merge(
    var.settings.options,
    {
      target = {
        nodeNames      = local.node_names
        taintSelectors = [for t in var.settings.taint_selectors : { for k, v in t : k => v if v != null }]
      }
      categories = [
        for c in var.settings.categories : merge(
          { domain = c.domain, variant = c.variant },
          c.options == null ? {} : { options = c.options },
        )
      ]
    },
    var.settings.gang_scheduler == null ? {} : {
      gangScheduler = merge(
        { schedulerName = var.settings.gang_scheduler.scheduler_name },
        var.settings.gang_scheduler.queue == null ? {} : { queue = var.settings.gang_scheduler.queue },
      )
    },
  )
}

# NVCRE makes the whole spec immutable (CEL: self == oldSelf), so a
# certificate can only be re-earned by a new Certification. This is the list of
# things that, when any of them changes, make the old certificate stale:
# the cluster, its version, the exact instances, the launch template each pool
# boots from, the stack, and the spec itself.
resource "terraform_data" "identity" {
  triggers_replace = {
    endpoint       = var.cluster_endpoint
    version        = var.cluster_version
    instances      = local.provider_ids
    pools          = var.pool_identity
    stack_revision = var.stack_revision
    spec           = jsonencode(local.spec)
  }
}

resource "kubernetes_manifest" "certification" {
  manifest = {
    apiVersion = "nvcre.nvidia.com/v1alpha1"
    kind       = "Certification"
    metadata = {
      name      = var.settings.name
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = local.spec
  }

  lifecycle {
    # Destroy-first replacement (no create_before_destroy): two certifications
    # must never contend for the same GPUs.
    replace_triggered_by = [terraform_data.identity]

    # Gate: the census must hold before NVCRE sees the Certification.
    action_trigger {
      events  = [before_create]
      actions = [action.kubewait_condition.gpu_census]
    }

    # Hook: the apply is not done until the Certification is terminal.
    # taint: a failed certification is re-run by the next `up`, which
    # replaces it (the spec is immutable, so a re-run is always a replace).
    action_trigger {
      events     = [after_create]
      actions    = [action.kubewait_condition.certification_terminal]
      on_failure = taint
    }

    # Confirmation: teardown does not move past the Certification until the
    # TrainJobs and pods it spawned are gone (ADR-025 decision 6).
    action_trigger {
      events  = [after_destroy]
      actions = [action.kubewait_condition.trainjobs_drained, action.kubewait_condition.pods_drained]
    }
  }
}

# ---------------------------------------------------------------------------
# The waits. HCL for the spec in ../../kubewait-action.md §The five uses.
# ---------------------------------------------------------------------------

# 1. GPU census. AICR UAT's gpu_census_verdict (tests/uat/lib/phases.sh),
#    plus allocatable GPUs: exactly the expected count of nodes, all Ready,
#    none cordoned, none still carrying nodewright's (or legacy skyhook's)
#    runtime-required NoSchedule taint, each advertising its GPUs. The set
#    must be the nodes the plan named, or the Certification would target
#    stale names.
action "kubewait_condition" "gpu_census" {
  config {
    api_version        = "v1"
    kind               = "Node"
    label_selector     = join(",", [for k, v in var.settings.node_selector : "${k}=${v}"])
    min_matching       = var.expected_nodes
    max_matching       = var.expected_nodes
    require_all        = true
    success_conditions = [{ type = "Ready", status = "True" }]
    expression         = <<-CEL
      !(has(object.spec.unschedulable) && object.spec.unschedulable) &&
      !(has(object.spec.taints) && object.spec.taints.exists(t, t.effect == "NoSchedule" &&
          (t.key.startsWith("nodewright.nvidia.com") || t.key.startsWith("skyhook.nvidia.com")))) &&
      has(object.status.allocatable) && "nvidia.com/gpu" in object.status.allocatable &&
      int(object.status.allocatable["nvidia.com/gpu"]) >= ${var.settings.gpus_per_node}
    CEL
    set_expression     = "objects.all(o, o.metadata.name in ${jsonencode(local.node_names)})"
    timeout            = var.settings.census_timeout
    settle             = "20s"
    poll_interval      = "10s"
    progress_fields    = ["metadata.name", "spec.taints", "status.allocatable"]
  }
}

# 2. Certification terminal status: Succeeded=True or Failed=True. There is no
#    status.phase. settle covers the one non-monotonic case: with
#    repeatCount > 1 the controller can move Failed back to InProgress when a
#    child Workflow restarts.
action "kubewait_condition" "certification_terminal" {
  config {
    api_version        = "nvcre.nvidia.com/v1alpha1"
    kind               = "Certification"
    namespace          = var.settings.namespace
    name               = var.settings.name
    success_conditions = [{ type = "Succeeded", status = "True" }]
    failure_conditions = [{ type = "Failed", status = "True" }]
    absent             = "failure"
    timeout            = var.settings.wait_timeout
    settle             = var.settings.settle
    poll_interval      = "30s"
    progress_fields    = ["status.conditions", "status.categoryStatuses"]
    progress_interval  = "2m"
  }
}

# 3. Teardown drains. At v0.2.0 NVCRE creates Workflows, Jobs and their
#    dependents in the Certification's own namespace (certification_controller.go
#    :523, workflow_controller.go :1013 and :3072-3074), so the namespace is
#    the selector.
action "kubewait_condition" "trainjobs_drained" {
  config {
    api_version     = "trainer.kubeflow.org/v1alpha1"
    kind            = "TrainJob"
    namespace       = var.settings.namespace
    min_matching    = 0
    max_matching    = 0
    timeout         = var.settings.drain_timeout
    progress_fields = ["metadata.name"]
  }
}

action "kubewait_condition" "pods_drained" {
  config {
    api_version     = "v1"
    kind            = "Pod"
    namespace       = var.settings.namespace
    min_matching    = 0
    max_matching    = 0
    timeout         = var.settings.drain_timeout
    progress_fields = ["metadata.name", "spec.nodeName"]
  }
}
