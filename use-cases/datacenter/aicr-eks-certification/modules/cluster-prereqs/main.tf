# In-cluster prerequisites that must exist before any node boots.
#
# Upstream (mchmarny/cluster provider/eks/terraform @ 0ac8457) rendered these
# ENIConfigs to a local_file and applied them with a local-exec provisioner:
#
#   aws eks update-kubeconfig --region ... --name ...
#   kubectl apply -f eni-config.yaml
#
# A provisioner runs at create time only, so the objects were never updated
# when subnets changed, never deleted on destroy, and invisible to refresh.
# Here they are ordinary resources: planned, diffed, and destroyed through the
# old cluster's endpoint during teardown.
#
# The ENIConfig CRD (eniconfigs.crd.k8s.amazonaws.com) ships with the aws-node
# DaemonSet EKS installs at cluster creation [verify on the pinned EKS version],
# so these can be planned once the cluster exists: the provider configuration
# is unknown until then, and the engine defers them (provider_config_unknown).

locals {
  # Tolerations for add-ons that run on all nodes (vpc-cni, cloudwatch agent).
  # Ported from upstream cluster.tf; ../eks-compute/addons.tf carries a copy
  # for the cloudwatch agent.
  all_node_tolerations = [
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "system-workload"
      effect   = "NoSchedule"
    },
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "system-workload"
      effect   = "NoExecute"
    },
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "worker-workload"
      effect   = "NoSchedule"
    },
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "worker-workload"
      effect   = "NoExecute"
    },
    {
      operator = "Exists"
    }
  ]
}

# Same content as upstream's templates/eni-config.ytpl: one object per zone,
# named after the zone (ENI_CONFIG_LABEL_DEF = topology.kubernetes.io/zone).
resource "kubernetes_manifest" "eniconfig" {
  for_each = var.eni_configs

  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      securityGroups = [each.value.security_group_id]
      subnet         = each.value.subnet_id
    }
  }
}

# Ported from upstream cluster.tf. Moved here because it must follow the
# ENIConfigs (upstream: depends_on = [local_file.eniconfig]) and precede every
# node group: ../eks-compute depends on this whole module, so custom
# networking is configured before a node can boot with the default layout.
resource "aws_eks_addon" "vpc_cni" {
  count = var.vpc_cni_version != null ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_version == "" ? null : var.vpc_cni_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    tolerations         = local.all_node_tolerations
    enableNetworkPolicy = "true"
    init = {
      env = {
        DISABLE_TCP_EARLY_DEMUX = "true"
      }
    }
    env = {
      ENABLE_POD_ENI                     = "false"
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
      ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
      POD_SECURITY_GROUP_ENFORCING_MODE  = "standard"
      AWS_VPC_K8S_CNI_EXTERNALSNAT       = "false"
      MINIMUM_IP_TARGET                  = tostring(var.networking.vpc_cni_minimum_ip_target)
      WARM_IP_TARGET                     = tostring(var.networking.vpc_cni_warm_ip_target)
    }
  })

  depends_on = [kubernetes_manifest.eniconfig]

  tags = { Name = "${var.prefix}-vpc-cni" }
}
