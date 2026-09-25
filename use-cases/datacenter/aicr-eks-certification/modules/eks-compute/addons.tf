# Ported from github.com/mchmarny/cluster provider/eks/terraform/cluster.tf @ 0ac8457
# (MIT, Copyright (c) 2025 Mark Chmarny; see LICENSE in this directory).
# Changes: moved here from cluster.tf and made to depend on the node groups.
#
# These four add-ons run as Deployments. Upstream created them alongside the
# node groups in one apply and relied on nodes arriving in time. Once deferral
# splits the work into rounds, "in time" is no longer guaranteed, so the edge is
# explicit: every add-on here waits for the system node group and the worker
# ASGs. kube-proxy stays with the cluster (../eks-cluster) and vpc-cni with the
# ENIConfigs (../cluster-prereqs); both are DaemonSets that must precede nodes.

locals {
  # Tolerations for system-only add-ons (coredns, metrics-server, ebs-csi controller)
  system_tolerations = [
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
      operator = "Exists"
    }
  ]

  # Tolerations for add-ons that run on all nodes (vpc-cni, cloudwatch agent)
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


  # #10: Normalize addon versions — empty string means latest (null)
  addon_versions = {
    for k, v in var.add_ons :
    k => v == "" ? null : v
  }

}

resource "aws_eks_addon" "coredns" {
  count = var.add_ons.core_dns != null ? 1 : 0

  addon_name                  = "coredns"
  addon_version               = local.addon_versions.core_dns
  cluster_name                = var.cluster.name
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    tolerations = local.system_tolerations
    corefile    = <<-EOT
    .:53 {
        errors
        health {
            lameduck 5s
          }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf {
          except s8k.io
        }
        forward s8k.io 205.251.192.116 205.251.199.66 205.251.194.44 205.251.196.207
        cache 30
        loop
        reload
        loadbalance
    }
EOT
  })

  tags = { Name = "${local.prefix}-coredns" }

  depends_on = [aws_eks_node_group.system, aws_autoscaling_group.node_groups]
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.add_ons.cloudwatch_observability != null ? 1 : 0

  cluster_name                = var.cluster.name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = local.addon_versions.cloudwatch_observability
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = var.addon_role_arns.cloudwatch_observability

  configuration_values = jsonencode({
    manager = {
      tolerations = local.system_tolerations
    }
    agent = {
      name        = "cw-observability"
      tolerations = local.all_node_tolerations
    }
  })

  tags = { Name = "${local.prefix}-cloudwatch-observability" }

  depends_on = [aws_eks_node_group.system, aws_autoscaling_group.node_groups]
}

resource "aws_eks_addon" "metrics_server" {
  count = var.add_ons.metrics_server != null ? 1 : 0

  cluster_name                = var.cluster.name
  addon_name                  = "metrics-server"
  addon_version               = local.addon_versions.metrics_server
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    tolerations = local.system_tolerations
  })

  tags = { Name = "${local.prefix}-metrics-server" }

  depends_on = [aws_eks_node_group.system, aws_autoscaling_group.node_groups]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.add_ons.ebs_csi != null ? 1 : 0

  cluster_name                = var.cluster.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = local.addon_versions.ebs_csi
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = var.addon_role_arns.ebs_csi

  configuration_values = jsonencode({
    controller = {
      tolerations = local.system_tolerations
    }
  })

  tags = { Name = "${local.prefix}-ebs-csi-driver" }

  depends_on = [aws_eks_node_group.system, aws_autoscaling_group.node_groups]
}
