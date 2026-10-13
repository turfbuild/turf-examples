output "release" {
  value = helm_release.podinfo.name
}

output "namespace" {
  value = helm_release.podinfo.namespace
}
