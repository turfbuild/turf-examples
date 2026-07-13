output "namespace" {
  description = "Kubernetes namespace where the application is deployed"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "deployment_name" {
  description = "Name of the php-apache deployment"
  value       = kubernetes_deployment_v1.php_apache.metadata[0].name
}

output "service_name" {
  description = "Name of the php-apache service"
  value       = kubernetes_service_v1.php_apache.metadata[0].name
}

output "hpa_name" {
  description = "Name of the Horizontal Pod Autoscaler"
  value       = kubernetes_horizontal_pod_autoscaler_v1.php_apache.metadata[0].name
}
