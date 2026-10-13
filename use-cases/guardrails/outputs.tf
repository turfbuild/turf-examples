output "release" {
  value = module.app.release
}

output "app_ref" {
  description = "The commit the podinfo module was pinned to"
  value       = var.app_ref
}
