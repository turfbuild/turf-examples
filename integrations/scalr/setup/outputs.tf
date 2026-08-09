output "hostname" {
  description = "Scalr hostname to put in the examples' backend blocks."
  value       = var.scalr_hostname
}

output "environment_name" {
  description = "The `organization` value for the remote backend blocks."
  value       = scalr_environment.demo.name
}

output "environment_id" {
  description = "Scalr environment ID (env-...)."
  value       = scalr_environment.demo.id
}

output "chat_workspace" {
  description = "Workspace whose region/greeting variables the chat/ demo pulls via the Scalr MCP server."
  value       = scalr_workspace.chat.name
}

output "policy_group_id" {
  description = "OPA policy group ID (null unless a vcs_token was supplied)."
  value       = one(scalr_policy_group.opa[*].id)
}

output "module_sources" {
  description = "Four-part Scalr registry sources for the published modules, keyed by module_repos label (empty unless a vcs_token was supplied). Consume each with a pinned version."
  value       = { for k, m in scalr_module.registry : k => "${var.scalr_hostname}/${m.source}" }
}

output "module_source" {
  description = "Convenience alias for module_sources[\"vpc\"] — the region-consuming module the chat/ demo pulls (null unless published)."
  value       = try("${var.scalr_hostname}/${scalr_module.registry["vpc"].source}", null)
}
