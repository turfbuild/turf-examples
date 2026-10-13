# A node is in maintenance while its name is in var.maintenance. Adding a name
# cordons the node, drains it and waits until it is empty. Removing the name
# uncordons it. terraform_data.maintenance holds one instance per node in
# maintenance, and its lifecycle triggers run the steps.

# Every node in the cluster. The steps are keyed by these names, so a name in
# var.maintenance that is not a node fails the plan.
data "kubernetes_nodes" "all" {}

locals {
  nodes = toset([for n in data.kubernetes_nodes.all.nodes : n.metadata[0].name])

  # kubectl talks to the same cluster as the providers.
  kubectl_flags = concat(
    ["--kubeconfig", pathexpand(var.kubeconfig_path)],
    var.kubeconfig_context == "" ? [] : ["--context", var.kubeconfig_context],
  )
}

resource "terraform_data" "maintenance" {
  for_each = var.maintenance
  input    = each.key

  lifecycle {
    # The steps run in order, and the first failure stops the rest. It also
    # fails the run and taints the instance, so the next run replaces it and
    # starts again from the cordon.
    action_trigger {
      events = [after_create]
      actions = [
        action.local_command.cordon[each.key],
        action.local_command.drain[each.key],
        action.kubewait_condition.drained[each.key],
      ]
      on_failure = taint
    }

    # Before the instance goes. If the uncordon fails, the destroy does not
    # happen, and the next run tries again.
    action_trigger {
      events  = [before_destroy]
      actions = [action.local_command.release]
    }
  }
}

action "local_command" "cordon" {
  for_each = local.nodes
  config {
    command   = "kubectl"
    arguments = concat(["cordon", each.key], local.kubectl_flags)
  }
}

# kubectl drain evicts the node's pods and waits for them to be deleted.
action "local_command" "drain" {
  for_each = local.nodes
  config {
    command   = "kubectl"
    arguments = concat(["drain", each.key], var.drain_flags, local.kubectl_flags)
  }
}

# Confirms what the drain should have left: nothing but DaemonSet pods, static
# (mirror) pods and pods that have finished. It only reads, and the verdict must
# hold for `settle` before it counts.
action "kubewait_condition" "drained" {
  for_each = local.nodes
  config {
    api_version     = "v1"
    kind            = "Pod"
    field_selector  = "spec.nodeName=${each.key}"
    filter          = <<-CEL
      !(has(object.metadata.ownerReferences) && object.metadata.ownerReferences.exists(r, r.kind == 'DaemonSet')) &&
      !(has(object.metadata.annotations) && 'kubernetes.io/config.mirror' in object.metadata.annotations) &&
      !(has(object.status.phase) && object.status.phase in ['Succeeded', 'Failed'])
    CEL
    min_matching    = 0
    max_matching    = 0
    settle          = "10s"
    timeout         = "5m"
    progress_fields = ["metadata.namespace", "metadata.name", "status.phase"]
  }
}

# Uncordons the node whose instance is being destroyed. `caller` is that
# instance, so this works for any node in state, including one that has since
# left the cluster: such a node has nothing to uncordon.
#
# A retry replaces a tainted instance, and the replace destroys the old one
# first. The node is still in var.maintenance then, so the command is `true`,
# a no-op. A trigger `condition` cannot do this, because Terraform rejects
# conditions on destroy events.
action "local_command" "release" {
  config {
    command   = contains(var.maintenance, caller.input) ? "true" : "sh"
    arguments = concat(["-c", local.release_script, caller.input], local.kubectl_flags)
  }
}

locals {
  # $0 is the node and "$@" the kubectl flags.
  release_script = <<-EOT
    found=$(kubectl get node "$0" --ignore-not-found -o name "$@") || exit 1
    if [ -z "$found" ]; then echo "node/$0 is gone; nothing to uncordon"; exit 0; fi
    kubectl uncordon "$0" "$@"
  EOT
}
