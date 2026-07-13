# Namespace for the example workload
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      example = "kubernetes-backend"
    }
  }
}

# A simple ConfigMap to demonstrate state management.
# Update the greeting or environment variables to see in-place updates.
resource "kubernetes_config_map_v1" "example" {
  metadata {
    name      = "example-config"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      example = "kubernetes-backend"
    }
  }

  data = {
    greeting    = var.greeting
    environment = var.environment
  }
}
