output "resource_id" {
  description = "id of the resource the actions gate"
  value       = tfcoremock_simple_resource.web.id
}

output "resource_string" {
  description = "the resource's string attribute"
  value       = tfcoremock_simple_resource.web.string
}
