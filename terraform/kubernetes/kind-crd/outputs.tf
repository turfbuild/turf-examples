output "cluster_name" {
  description = "Full name of the kind cluster; the kubectl context is kind-<this>"
  value       = kind_cluster.demo.name
}

output "cluster_endpoint" {
  description = "API server endpoint of the kind cluster"
  value       = kind_cluster.demo.endpoint
}

output "crd_name" {
  description = "Name of the registered CustomResourceDefinition"
  value       = kubernetes_manifest.crd.manifest.metadata.name
}

output "cr_name" {
  description = "Name of the example custom resource"
  value       = kubernetes_manifest.instance.manifest.metadata.name
}

output "cr_message" {
  description = "spec.message on the example custom resource"
  value       = kubernetes_manifest.instance.manifest.spec.message
}
