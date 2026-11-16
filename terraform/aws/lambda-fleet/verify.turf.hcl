# The rollout's verify step, as a Turf action. tofu and terraform ignore this
# file by its name; Turf lays it over main.tf at every plan.
#
# A turf_action is the built-in action the agent driving Turf carries out
# itself: the apply stops at awaiting_actions with the prompt and inputs, the
# agent does the step with its own tools, and answers with
# apply(action_results). Here the agent fetches every function URL and proves
# the deployed greeting is the one the configuration declares.

action "turf_action" "verify" {
  config {
    prompt = <<-EOT
      The fleet was just deployed or patched. Fetch every URL in inputs.urls
      with an HTTP GET. Each must answer HTTP 200 with a JSON body whose
      "message" equals inputs.greeting. A URL may take a few seconds to go
      live: retry it up to three times. Report one progress line per function,
      with the URL and the message it returned. Fail, naming the URL, if any
      does not answer as expected.
    EOT
    inputs = {
      greeting = caller.output.greeting
      urls     = caller.output.urls
    }
  }
}

action_trigger "verify" {
  target     = terraform_data.rollout
  events     = [after_create, after_update]
  actions    = [action.turf_action.verify]
  on_failure = halt
}
