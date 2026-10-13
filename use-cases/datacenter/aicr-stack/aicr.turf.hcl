# Turf actions: the steps a person or an agent performs around this stack.
# tofu and terraform ignore this file by its name; Turf lays it over the
# configuration at every plan. Both actions are turf_action, the built-in
# action the agent driving Turf carries out itself (no provider plugin): the
# apply stops at awaiting_actions with the prompt and inputs, the agent does
# the step with its own tools, and answers with apply(action_results).

# Certification: runs once the GPU Operator's release has landed, which is
# the point where the runtime is either healthy or not. A failure taints the
# release, so the next up replaces it.
action "turf_action" "certify" {
  config {
    prompt = <<-EOT
      Certify the runtime. In kube context kind-${var.cluster_name}-${var.generation},
      read the ClusterPolicy (kubectl get clusterpolicy -o json) and fail unless
      status.state is "ready". Report the node count, the GPU count (sum of
      status.allocatable["nvidia.com/gpu"] across nodes; zero on a laptop) and
      the ClusterPolicy's reason, each as a progress line.
    EOT
    inputs = {
      release   = caller.name
      namespace = caller.namespace
      context   = "kind-${var.cluster_name}-${var.generation}"
    }
  }
}

action_trigger "certify" {
  target     = module.stack.module.gpu_operator.helm_release.this
  events     = [after_create]
  actions    = [action.turf_action.certify]
  on_failure = taint
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
      Ask the user whether cluster ${var.cluster_name}-${var.generation} is ready
      to hand over to its tenant. Quote their answer in progress. Succeed only if
      they say yes; if they decline, fail with their reason.
    EOT
    inputs = {
      cluster = "${var.cluster_name}-${var.generation}"
    }
  }
}
