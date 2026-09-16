output "cluster_name" {
  description = "kind cluster name, including the generation suffix; the kubectl context is kind-<this>"
  value       = kind_cluster.dc.name
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig the kind provider wrote for this cluster"
  value       = kind_cluster.dc.kubeconfig_path
}

output "namespaces" {
  description = "Namespace each component was installed into"
  value = merge(
    {
      gpu_operator = module.gpu_operator.namespace
      nim_operator = module.nim_operator.namespace
    },
    length(module.cert_manager) > 0 ? { cert_manager = module.cert_manager[0].namespace } : {},
    length(module.external_dns) > 0 ? { external_dns = module.external_dns[0].namespace } : {},
  )
}

output "chart_versions" {
  description = "Chart version actually deployed for each component"
  value = merge(
    {
      gpu_operator = module.gpu_operator.chart_version
      nim_operator = module.nim_operator.chart_version
    },
    length(module.cert_manager) > 0 ? { cert_manager = module.cert_manager[0].chart_version } : {},
    length(module.external_dns) > 0 ? { external_dns = module.external_dns[0].chart_version } : {},
  )
}

output "gpu_node_label" {
  description = <<-EOT
    The label both operators are waiting for. The GPU Operator gates every
    operand on it; the NIM Operator puts it on the nodeSelector of the pod that
    pulls a model. Nothing in this stack schedules a GPU workload until some node
    carries it.
  EOT
  value       = module.gpu_operator.gpu_node_label
}

output "nim_crd_kinds" {
  description = "Custom resource kinds the NIM Operator installed"
  value       = module.nim_operator.crd_kinds
}
