output "cluster_name" {
  value = kind_cluster.dc.name
}

output "components" {
  description = "Every component this recipe deployed, in no particular order"
  value = [
    module.agentgateway_crds.release_id,
    module.agentgateway_crds_post.release_id,
    module.cert_manager.release_id,
    module.agentgateway.release_id,
    module.agentgateway_post.release_id,
    module.nfd.release_id,
    module.network_operator.release_id,
    module.nodewright_operator.release_id,
    module.prometheus_operator_crds.release_id,
    module.kube_prometheus_stack.release_id,
    module.gpu_operator.release_id,
    module.k8s_ephemeral_storage_metrics.release_id,
    module.kai_scheduler.release_id,
    module.nvidia_dra_driver_gpu.release_id,
    module.nvsentinel.release_id,
    module.prometheus_adapter.release_id,
  ]
}
