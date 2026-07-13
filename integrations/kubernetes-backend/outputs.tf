output "namespace" {
  description = "Kubernetes namespace where the workload is deployed"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "config_map_name" {
  description = "Name of the example ConfigMap"
  value       = kubernetes_config_map_v1.example.metadata[0].name
}

output "state_secret_name" {
  description = "Name of the Kubernetes Secret storing the OpenTofu state (default workspace)"
  value       = "tfstate-default-demo"
}

output "state_namespace" {
  description = "Namespace where the state Secret is stored"
  value       = "turf-state"
}
