output "name" {
  value = var.settings.name
}

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "uid" {
  description = "The Certification's UID; changes whenever a new certification is created."
  value       = kubernetes_manifest.certification.object.metadata.uid
}

output "node_names" {
  description = "The nodes the Certification targets (target.nodeNames)."
  value       = local.node_names
}

output "spec" {
  value = local.spec
}

output "identity" {
  description = "Changes exactly when the certificate goes stale (terraform_data.identity is replaced)."
  value       = terraform_data.identity.id
}
