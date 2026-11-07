# A turf action: a step of the apply that the agent carries out, not a provider.
# After the Job is created, the apply pauses here until the agent reports that
# the Job completed. tofu and terraform ignore this file by its name.
action "turf_action" "wait_for_greeting" {
  config {
    prompt = "Wait for the Job ${caller.metadata[0].name} in namespace ${caller.metadata[0].namespace} to complete, using your Kubernetes tools: check the Job's status and its pod's events, and read the pod's log. Succeed when the Job has succeeded, quoting the log line it printed. Fail if the Job fails, or if its pod is still pending after about two minutes, with the pod's events and log as the error."
    inputs = {
      job       = caller.metadata[0].name
      namespace = caller.metadata[0].namespace
    }
  }
}

action_trigger "wait_for_greeting" {
  target     = module.greeting.kubernetes_job_v1.greet
  events     = [after_create]
  actions    = [action.turf_action.wait_for_greeting]
  on_failure = halt
}
