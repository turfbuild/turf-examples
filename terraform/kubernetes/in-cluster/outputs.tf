output "namespace" {
  description = "The namespace the greeting lives in."
  value       = module.greeting.namespace
}

output "config_map" {
  description = "The ConfigMap holding the greeting, as namespace/name."
  value       = module.greeting.config_map
}
