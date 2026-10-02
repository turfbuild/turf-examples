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
      cert_manager   = module.cert_manager.namespace
      gpu_operator   = module.gpu_operator.namespace
      slurm_operator = module.slurm_operator.namespace
      slurm          = module.slurm.namespace
    },
    { for k in module.kai_scheduler : "kai_scheduler" => k.namespace },
  )
}

output "chart_versions" {
  description = "Chart version actually deployed for each component"
  value = merge(
    {
      cert_manager   = module.cert_manager.chart_version
      gpu_operator   = module.gpu_operator.chart_version
      slurm_operator = module.slurm_operator.chart_version
      slurm          = module.slurm.chart_version
    },
    { for k in module.kai_scheduler : "kai_scheduler" => k.chart_version },
  )
}

output "queue" {
  description = "The KAI queue every Slurm pod is placed in, or null without KAI"
  value       = one(module.kai_scheduler[*].queue)
}

output "slurm_nodesets" {
  description = <<-EOT
    NodeSet → the Slurm node names its pods register as. On a cluster with no
    GPU the gpu-* names never appear in sinfo: their pods never schedule.
  EOT
  value       = module.slurm.nodesets
}

output "login" {
  description = "A shell on the Slurm login node"
  value       = "kubectl --context kind-${kind_cluster.dc.name} -n ${module.slurm.namespace} exec -it deploy/${module.slurm.login_deployment} -- bash"
}
