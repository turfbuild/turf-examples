output "nodes" {
  description = "Every node in the cluster"
  value       = sort(local.nodes)
}

output "in_maintenance" {
  description = "Nodes held in maintenance"
  value       = sort(keys(terraform_data.maintenance))
}
