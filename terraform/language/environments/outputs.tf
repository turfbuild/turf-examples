output "service" {
  description = "environment/name and the version it runs"
  value       = tfcoremock_simple_resource.service.string
}

output "replicas" {
  value = tfcoremock_simple_resource.service.integer
}
