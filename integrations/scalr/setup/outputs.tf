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

output "coded_workspace" {
  description = "Workspace name for ../state-backend (its `workspaces { name = ... }`)."
  value       = scalr_workspace.coded.name
}

output "plot_workspace" {
  description = "Workspace name for ../plot."
  value       = scalr_workspace.plot.name
}

output "policy_group_id" {
  description = "OPA policy group ID (null unless a vcs_token was supplied)."
  value       = one(scalr_policy_group.opa[*].id)
}
