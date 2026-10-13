# The promotion's two steps, as Turf actions — one file for both environments;
# a trigger's condition picks where each one fires. tofu and terraform ignore
# this file by its name; Turf lays it over main.tf at every plan.
#
# A turf_action is the built-in action the agent driving Turf carries out
# itself: the apply stops at awaiting_actions with the prompt and inputs, the
# agent does the step with its own tools, and answers with
# apply(action_results).

# Smoke: after a change lands, read the service back and report. A failure
# taints it, so the next up replaces it.
action "turf_action" "smoke" {
  config {
    prompt = <<-EOT
      The ${var.environment} service was just updated. Read it back
      (state_list with include_values, or show) and confirm its string carries
      v${var.app_version} and it runs ${var.replicas} replica(s). Report both as
      progress lines; fail if either is off.
    EOT
    inputs = { environment = var.environment, version = var.app_version, replicas = var.replicas }
  }
}

action_trigger "smoke" {
  target     = tfcoremock_simple_resource.service
  events     = [after_create, after_update]
  actions    = [action.turf_action.smoke]
  on_failure = taint
}

# Gate: production does not move until someone says staging has soaked. The
# condition keeps the question out of staging's own rollout.
action "turf_action" "gate" {
  config {
    prompt = <<-EOT
      Before production moves to v${var.app_version}: ask the user whether this
      version has soaked in staging long enough. Quote their answer in
      progress. Succeed only if they say yes; if they decline, fail with their
      reason — production stays where it is.
    EOT
    inputs = { version = var.app_version }
  }
}

action_trigger "gate" {
  target     = tfcoremock_simple_resource.service
  events     = [before_update]
  actions    = [action.turf_action.gate]
  condition  = var.environment == "production"
  on_failure = halt
}
