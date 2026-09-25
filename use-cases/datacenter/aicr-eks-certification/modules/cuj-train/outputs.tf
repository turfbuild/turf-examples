output "trainjob" {
  value = {
    name      = var.settings.name
    namespace = var.settings.namespace
    uid       = kubernetes_manifest.trainjob.object.metadata.uid
  }
}
