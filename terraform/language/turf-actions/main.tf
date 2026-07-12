# Turf-native actions — human-in-the-loop and agent steps in a plan.
#
# Action types prefixed `turf_` are built into Turf: they dispatch in-process
# (no provider plugin) and run during apply, wearing the synthetic provider
# identity `turfbuild/turf`. Two are available:
#
#   turf_confirm — elicits a continue/halt decision from a human.
#   turf_action  — delegates a step to the agent via MCP sampling; the agent
#                  performs it (optionally using other tools) and reports
#                  success or failure.
#
# Bind them to a resource's lifecycle with action_trigger, exactly like a
# provider action. They show up in the plan as action_invocations[] and run as
# gating `invoke` effects at apply.

resource "tfcoremock_simple_resource" "production_bucket" {
  id     = var.resource_id
  string = "production data store"

  lifecycle {
    # Human gate: before this resource is created, ask a person to approve.
    # A "halt" decision fails the invoke and leaves the create blocked.
    action_trigger {
      events  = [before_create]
      actions = [action.turf_confirm.approve]
    }

    # Agent hook: after creation, have the agent verify a safety property.
    # Its report drives success/failure; on_failure decides the consequence.
    action_trigger {
      events     = [after_create]
      actions    = [action.turf_action.verify]
      on_failure = halt
    }
  }
}

# turf_confirm: a human continue/halt gate. The client renders a two-choice
# control; the negative option names this trigger's on_failure (here: Halt).
action "turf_confirm" "approve" {
  config {
    message = "About to create the production data store. Proceed?"
  }
}

# turf_action: the agent performs the check and reports {succeeded, detail}.
# Frame what counts as failure directly in the prompt. `context` asks Turf to
# include the resource diff in the request so the agent can inspect it.
action "turf_action" "verify" {
  config {
    prompt  = "Verify the production data store is not publicly accessible. Fail if it is."
    context = "resource"
  }
}
