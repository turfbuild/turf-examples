output "cluster_endpoint" {
  description = "API server endpoint of the kind cluster"
  value       = kind_cluster.demo.endpoint
}

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.podinfo.name
}

output "release_namespace" {
  description = "Namespace the Helm release was installed into"
  value       = helm_release.podinfo.namespace
}

output "release_status" {
  description = "Status of the Helm release (deployed, failed, ...)"
  value       = helm_release.podinfo.status
}

output "chart_version" {
  description = "Resolved chart version that was installed"
  value       = helm_release.podinfo.version
}
