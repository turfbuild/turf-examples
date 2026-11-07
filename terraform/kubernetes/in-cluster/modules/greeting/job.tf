# A one-pod Job that reads the greeting back out of the ConfigMap and prints it.
# It is the workload step of this configuration: the apply creates it and goes
# on, and the turf action declared in ../../greeting.turf.hcl waits for it to
# finish. wait_for_completion stays off so the wait is the agent's, with its
# own tools, not the provider's.
resource "kubernetes_job_v1" "greet" {
  metadata {
    name      = "greet"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    backoff_limit = 0
    template {
      metadata {}
      spec {
        restart_policy = "Never"
        container {
          name    = "greet"
          image   = "busybox:1.37"
          command = ["sh", "-c", "echo \"$GREETING\""]
          env {
            name = "GREETING"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.greeting.metadata[0].name
                key  = "greeting"
              }
            }
          }
        }
      }
    }
  }
  wait_for_completion = false
}

output "job" {
  value = "${kubernetes_job_v1.greet.metadata[0].namespace}/${kubernetes_job_v1.greet.metadata[0].name}"
}
