output "cluster_name" {
  value = var.cluster_name
}

output "criteria" {
  description = "The AICR criteria the bundle was resolved from"
  value       = module.stack.criteria
}

output "releases" {
  description = "Every release the bundle installed, name -> namespace"
  value       = module.stack.releases
}

output "namespaces" {
  description = "Distinct namespaces the bundle installs into"
  value       = module.stack.namespaces
}
