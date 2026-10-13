# The two steps of the runbook that are a person's or the agent's, as Turf
# actions. tofu and terraform ignore this file by its name; Turf lays it over
# main.tf at every plan. A turf_action is the built-in action the agent
# driving Turf carries out itself: the apply stops at awaiting_actions with
# the prompt and inputs, the agent does the step with its own tools, and
# answers with apply(action_results).
#
# Both read their node from `caller`, the record whose step they are, so one
# declaration serves every node in the set.

# The maintenance window: a decision only the operator makes, so the agent
# asks, before the node is touched. A "no" fails the step with their reason,
# and the halt means the record is never created: nothing was cordoned.
action "turf_action" "window" {
  config {
    prompt = <<-EOT
      Ask the user whether the maintenance window for node ${caller.input} is
      open now. Quote their answer in progress. Succeed only if they say yes;
      if they decline, fail with their reason.
    EOT
    inputs = { node = caller.input }
  }
}

action_trigger "window" {
  target     = terraform_data.maintenance
  events     = [before_create]
  actions    = [action.turf_action.window]
  on_failure = halt
}

# The repair. In a datacenter this is where the provider's host playbook runs:
# a firmware reflash, a reboot, a replacement. Here the agent inspects the
# drained node and reports what it found.
action "turf_action" "repair" {
  config {
    prompt = <<-EOT
      Node ${caller.input} is cordoned and drained. Inspect it: run
      `kubectl describe node ${caller.input}` (with the kubeconfig flags in
      inputs) and report its conditions and any taints or events worth
      knowing, each as a progress line. In a datacenter this is where the host
      playbook runs; here there is nothing to repair. Fail if the node is
      NotReady or missing.
    EOT
    inputs = {
      node          = caller.input
      kubectl_flags = local.kubectl_flags
    }
  }
}

# The second half of the runbook: repair, then re-certify (the Ready wait
# declared in main.tf, this record's node's: a declaration binds every record
# of its target, and each.key is that record's). Turf splices an overlay's
# triggers after the resource's own, so these run once main.tf's cordon →
# drain → drained chain has passed.
action_trigger "repair_and_recertify" {
  target     = terraform_data.maintenance
  events     = [after_create]
  actions    = [action.turf_action.repair, action.kubewait_condition.ready[each.key]]
  on_failure = taint
}
