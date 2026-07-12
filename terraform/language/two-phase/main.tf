# Staged-then-committed apply: the "commit" pattern with Terraform Actions.
#
# Some systems don't apply a change the moment you write it — they *stage* a
# candidate change, then require an explicit, atomic *commit* to make it live.
# Network devices (stage a candidate config, then `commit`), some databases
# (stage a migration, then run it), and feature-flag/config services all work
# this way.
#
# You model that shape with a resource that stages the change plus an
# `after_create`/`after_update` action that commits it: the resource write puts
# the candidate in place, and the gated action seals it. If the commit action
# fails (on_failure = halt, the default), the run stops before anything downstream
# proceeds — the atomic-commit boundary.

# The staged candidate config (a real provider would push this to the device as a
# candidate, not the running config).
resource "tfcoremock_simple_resource" "candidate" {
  id     = var.device_id
  string = var.candidate_config

  lifecycle {
    # Commit the candidate after it is staged on create, and again after any
    # update re-stages it. halt (default) means a failed commit stops the run.
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.tfcoremock_simple_resource.commit]
    }
  }
}

# The atomic commit step. Against a real provider this would be the device's
# `commit` action (or a DB "run migration" action); here it's an echo action.
action "tfcoremock_simple_resource" "commit" {
  config {
    string = "commit candidate ${var.device_id}"
  }
}
