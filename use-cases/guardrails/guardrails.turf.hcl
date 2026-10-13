# The two guardrails that ride with the configuration, as Turf actions on the
# pet the workload is named after. tofu and terraform ignore this file by its
# name; Turf lays it over main.tf at every plan. Both are before_create with
# halt: a failure stops the pet and the app that waits on it (the cluster,
# which depends on neither, still applies). They stop the apply even when it
# runs unattended (auto_approve) — an apply-time step the author wrote in, not
# a second approval.
#
# A turf_action is the built-in action the agent driving Turf carries out
# itself: the apply stops at awaiting_actions with the prompt and inputs, the
# agent does the step with its own tools, and answers with
# apply(action_results).

# Attest: every provider this configuration runs was scanned, in this session,
# and none was blocked. init reports each provider's package_dir and hashes;
# the scan (trivy, grype, or their MCP servers) reads those directories before
# workspace_open. This step asks the agent to stand behind it.
action "turf_action" "attest" {
  config {
    prompt = <<-EOT
      Attest the provider scan. Confirm that every provider init installed for
      this configuration (kind, helm, random) was scanned in this session, by
      package directory, and that no verdict blocked one. List each provider
      and its verdict as a progress line. If any was not scanned, or was
      blocked, fail naming it.
    EOT
  }
}

# Check: the policies in policies/ hold for what is about to be created. The
# same rego the approval-point check ran; here it runs against the planned
# values the apply is about to use.
action "turf_action" "check" {
  config {
    prompt = <<-EOT
      Evaluate policies/*.rego (package terraform, rule deny) against this
      plan: run `opa eval` or `conftest` on the plan document, or on an
      input.tfplan built from inputs if the document is gone. Fail on any deny,
      quoting each reason as an error; otherwise report "no denials" as
      progress.
    EOT
    inputs = { address = "random_pet.name", length = caller.length }
  }
}

action_trigger "guardrails" {
  target     = random_pet.name
  events     = [before_create]
  actions    = [action.turf_action.attest, action.turf_action.check]
  on_failure = halt
}
