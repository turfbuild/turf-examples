output "cluster" {
  value = {
    name     = module.eks_cluster.cluster_name
    version  = module.eks_cluster.cluster_version
    endpoint = module.eks_cluster.endpoint
    oidc     = module.eks_cluster.oidc
  }
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.deployment.location} --name ${module.eks_cluster.cluster_name}"
}

# Upstream's ClusterStatus, as state rather than a file next to the config.
output "status" {
  value = merge(module.eks_cluster.status, {
    compute = {
      systemNodeGroup = module.eks_compute.system_node_group
      workerPools     = module.eks_compute.worker_pools
      addons          = merge(module.eks_compute.addons, module.cluster_prereqs.vpc_cni == null ? {} : { vpcCni = module.cluster_prereqs.vpc_cni })
    }
  })
}

output "certification" {
  description = "Which nodes were certified, by which Certification. The apply that produced this output waited for it to succeed."
  value = {
    name       = module.certification.name
    namespace  = module.certification.namespace
    uid        = module.certification.uid
    node_names = module.certification.node_names
  }
}

output "cuj_train" {
  value = one(module.cuj_train[*].trainjob)
}

output "certification_identity" {
  description = "Changes exactly when the certificate goes stale; see modules/certification terraform_data.identity."
  value       = module.certification.identity
}
