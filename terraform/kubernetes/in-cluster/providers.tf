# Empty kubeconfig_path (the default) leaves the provider unconfigured, and in
# a pod it then uses the pod's service account (KUBERNETES_SERVICE_HOST).
provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}
