# Terraform Actions — action blocks + lifecycle.action_trigger.
#
# An `action` is an imperative, non-persistent operation a provider exposes (it
# writes no state). A resource's `lifecycle.action_trigger` invokes one or more
# actions around a lifecycle event (before_create, after_create, before_update,
# after_update, before_destroy, after_destroy). Turf runs each triggered action
# as a gating "invoke" effect, ordered relative to the resource operation.

resource "tfcoremock_simple_resource" "web" {
  id     = var.resource_id
  string = "web-server"

  lifecycle {
    # A pre-flight gate: this action must succeed before the resource is created.
    # Model checks like "the change window is open" or "a policy check passes".
    action_trigger {
      events  = [before_create]
      actions = [action.tfcoremock_simple_resource.preflight_gate]
    }

    # A post-create hook: fires after the resource exists. Model side effects
    # like "announce the deployment" or "warm a cache".
    action_trigger {
      events  = [after_create]
      actions = [action.tfcoremock_simple_resource.announce]

      # on_failure controls what happens if the action errors: `halt` (default)
      # stops the run; `continue` records the failure and proceeds. A post-create
      # announcement is non-critical, so let the run continue if it fails.
      on_failure = continue
    }
  }
}

# The gate and the hook are echo actions here (tfcoremock just marshals their
# config). Against a real provider these would be, e.g., aws_lambda_invoke or a
# local_command — see the README.
action "tfcoremock_simple_resource" "preflight_gate" {
  config {
    string = "preflight: change window open"
  }
}

action "tfcoremock_simple_resource" "announce" {
  config {
    string = "announce: web-server deployed"
  }
}
