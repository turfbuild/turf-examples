variable "cluster_name" {
  description = "The workload cluster the runtime is installed on."
  type        = string
}

variable "clusters_dir" {
  description = <<-EOT
    Where the engine keeps one kubeconfig per workload cluster, as
    <clusters_dir>/<cluster_name>.kubeconfig. In a management cluster this is a
    Secret mounted into the engine's pods, one key per cluster: adding a
    cluster is adding a key.
  EOT
  type        = string
  default     = "/turf/clusters"
}

variable "kubeconfig" {
  description = "Path of the cluster's kubeconfig where the engine runs. Overrides clusters_dir."
  type        = string
  default     = null
}

locals {
  kubeconfig = coalesce(var.kubeconfig, "${var.clusters_dir}/${var.cluster_name}.kubeconfig")
}
