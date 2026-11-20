# Turf actions: the steps a person or an agent performs around this stack.
# tofu and terraform ignore this file by its name; Turf lays it over the
# configuration at every plan. Both are turf_action, the built-in action the
# agent driving Turf carries out itself (no provider plugin): the apply stops
# at awaiting_actions with the prompt and inputs, the agent does the step with
# its own tools, and answers with apply(action_results).

# The maintenance window: the apply installs everything the GPU Operator
# depends on, then stops and waits for a person before the operator itself.
# On real nodes the operator's release is the one that touches every GPU host
# (driver, container toolkit, device plugin), so it is the one a person
# schedules. A "no" halts the round: what is installed stays, the operator and
# everything behind it wait for the next up.
action "turf_action" "maintenance_window" {
  config {
    prompt = <<-EOT
      The GPU Operator is next on cluster ${var.cluster_name}, and it changes
      every GPU node. Ask the user whether the maintenance window for
      ${var.cluster_name} is open. Quote their answer in progress. Succeed only
      if they say yes; if they decline, fail with their reason.
    EOT
    inputs = {
      cluster   = var.cluster_name
      release   = caller.name
      namespace = caller.namespace
      chart     = "${caller.chart} ${caller.version}"
    }
  }
}

action_trigger "maintenance_window" {
  target     = module.stack.module.gpu_operator.helm_release.this
  events     = [before_create]
  actions    = [action.turf_action.maintenance_window]
  on_failure = halt
}

# Handover: a decision only the operator can make, so it is declared here and
# not bound to a lifecycle event. Run it when the cluster is ready to leave
# your hands:
#
#   invoke({ action_addr: "action.turf_action.handover" })
#
# The agent asks the user and reports their answer; a "no" is a failure
# carrying their reason.
action "turf_action" "handover" {
  config {
    prompt = <<-EOT
      Ask the user whether cluster ${var.cluster_name} is ready to hand over to
      its tenant. Quote their answer in progress. Succeed only if they say yes;
      if they decline, fail with their reason.
    EOT
    inputs = {
      cluster = var.cluster_name
    }
  }
}
