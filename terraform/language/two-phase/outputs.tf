output "device_id" {
  description = "Identifier of the device whose config was staged and committed"
  value       = tfcoremock_simple_resource.candidate.id
}

output "committed_config" {
  description = "The candidate configuration that was staged then committed"
  value       = tfcoremock_simple_resource.candidate.string
}
