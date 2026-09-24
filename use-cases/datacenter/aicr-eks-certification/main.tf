# One graph: the EKS cluster, the in-cluster prerequisites, the nodes, the AICR
# stack, an NVCRE certification of the GPU pools, and a training smoke on top.
#
# In AICR's UAT the same lifecycle is three tools joined by CI: the
# mchmarny/cluster actuator (Terraform, cluster only), helmfile or Argo CD (the
# stack), and ~1,200 lines of GitHub Actions per cloud for the waits, the
# retries and the teardown. Here every step is a node, every wait is an action
# on the edge it guards, and teardown is the graph in reverse.
#
# This configuration is a target-state spec: it validates and its mocked tests
# pass, but no engine runs it end to end today. README.md §Prerequisites says
# exactly what is missing.

module "eks_cluster" {
  source = "./modules/eks-cluster"

  deployment    = var.deployment
  cluster       = var.cluster
  network       = var.network
  iam           = var.iam
  observability = var.observability
  security      = var.security
}

# ENIConfigs, then vpc-cni, before any node boots (upstream: local-exec kubectl).
module "cluster_prereqs" {
  source = "./modules/cluster-prereqs"

  prefix          = module.eks_cluster.prefix
  cluster_name    = module.eks_cluster.cluster_name
  eni_configs     = module.eks_cluster.eni_configs
  vpc_cni_version = var.cluster.add_ons.vpc_cni
  networking      = var.networking
}

module "eks_compute" {
  source = "./modules/eks-compute"

  prefix     = module.eks_cluster.prefix
  region     = module.eks_cluster.region
  account_id = module.eks_cluster.account_id
  tags       = var.deployment.tags

  cluster = {
    name                       = module.eks_cluster.cluster_name
    version                    = module.eks_cluster.cluster_version
    endpoint                   = module.eks_cluster.endpoint
    certificate_authority_data = module.eks_cluster.certificate_authority_data
    service_cidr               = module.eks_cluster.service_cidr
  }
  subnet_ids_by_type          = module.eks_cluster.subnet_ids_by_type
  system_subnet_ids           = module.eks_cluster.system_subnet_ids
  security_group_ids          = module.eks_cluster.security_group_ids
  worker_instance_profile_arn = module.eks_cluster.worker_instance_profile_arn
  system_node_role            = module.eks_cluster.system_node_role
  addon_role_arns             = module.eks_cluster.addon_role_arns

  ssh_public_key      = var.ssh_public_key
  system_pool         = var.system_pool
  worker_pools        = var.worker_pools
  autoscaling         = var.autoscaling
  metrics_granularity = var.observability.metrics_granularity
  add_ons = {
    core_dns                 = var.cluster.add_ons.core_dns
    cloudwatch_observability = var.cluster.add_ons.cloudwatch_observability
    metrics_server           = var.cluster.add_ons.metrics_server
    ebs_csi                  = var.cluster.add_ons.ebs_csi
  }

  # Custom networking must be in place before the first node boots. Upstream
  # left this to timing within one apply; deferral turns that into a round.
  depends_on = [module.cluster_prereqs]
}

# The boundary between "the cluster" and "what runs in it".
#
# - Containment: keyed on the endpoint, so replacing the cluster replaces
#   everything that depends on this (the bundle carries its own per-component
#   shims keyed the same way).
# - Teardown barrier: everything in-cluster depends on it, so it is destroyed
#   after the stack and before the nodes and the VPC. Its before_destroy gate
#   holds teardown until no LoadBalancer Service is left, because an in-tree
#   cloud-provider ELB and its k8s-elb-* security group live outside state and
#   pin the VPC (AICR #1617: DeleteVpc → DependencyViolation). Services the
#   graph created are already gone by then (helm uninstall); the gate only
#   catches what something else created, and it fails closed rather than
#   deleting them.
resource "terraform_data" "cluster_contents" {
  triggers_replace = module.eks_cluster.endpoint

  depends_on = [module.eks_compute]

  lifecycle {
    action_trigger {
      events  = [before_destroy]
      actions = [action.kubewait_condition.no_load_balancer_services]
    }
  }
}

action "kubewait_condition" "no_load_balancer_services" {
  config {
    api_version     = "v1"
    kind            = "Service"
    filter          = "object.spec.type == 'LoadBalancer'"
    min_matching    = 0
    max_matching    = 0
    timeout         = "10m"
    poll_interval   = "10s"
    progress_fields = ["metadata.namespace", "metadata.name", "status.loadBalancer.ingress"]
  }
}

# The AICR stack for eks/h100/ubuntu/training/kubeflow, plus nvcre. Generated
# by `aicr bundle --deployer terraform` (README.md §Regenerating bundle/).
module "stack" {
  source = "./bundle"

  cluster_endpoint = module.eks_cluster.endpoint

  depends_on = [terraform_data.cluster_contents]
}

module "certification" {
  source = "./modules/certification"

  cluster_endpoint = module.eks_cluster.endpoint
  cluster_version  = module.eks_cluster.cluster_version
  settings         = var.certification

  # What a certificate is a certificate OF: these pools, as launched now. Any
  # change here replaces the Certification (its spec is immutable).
  pool_identity = {
    for name in var.certification.pools : name => {
      launch_template_id      = module.eks_compute.worker_pools[name].launch_template_id
      launch_template_version = module.eks_compute.worker_pools[name].launch_template_version
      autoscaling_group       = module.eks_compute.worker_pools[name].autoscaling_group
    }
  }
  expected_nodes = sum([for name in var.certification.pools : var.worker_pools[name].capacity.desired])
  stack_revision = filesha256("${path.module}/bundle/recipe.yaml")

  # Load-bearing: the node list is read only after the stack has settled, and
  # nvcre's CRDs exist only once the stack has installed it.
  depends_on = [module.stack]
}

module "cuj_train" {
  source = "./modules/cuj-train"
  count  = var.cuj_train.enabled ? 1 : 0

  cluster_endpoint  = module.eks_cluster.endpoint
  certification_uid = module.certification.uid
  settings          = var.cuj_train

  # The GPUs are shared: the smoke runs after the certification has passed,
  # never alongside it.
  depends_on = [module.certification]
}
