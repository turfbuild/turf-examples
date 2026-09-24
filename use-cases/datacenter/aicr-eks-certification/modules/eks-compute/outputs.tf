# Compute's part of upstream's ClusterStatus, plus what the certification
# module needs to decide when a pool has changed underneath a certificate.

output "worker_pools" {
  description = "Per worker pool: launch template, ASG, capacity, the derived GPU family, and the EFA layout actually rendered."
  value = {
    for ng in local.worker_node_groups : ng.name => {
      instance_type           = aws_launch_template.node_groups["${local.prefix}-${ng.name}"].instance_type
      gpu_family              = local.gpu_family[ng.name]
      taints                  = local.node_group_taints[ng.name]
      launch_template_id      = aws_launch_template.node_groups["${local.prefix}-${ng.name}"].id
      launch_template_version = aws_launch_template.node_groups["${local.prefix}-${ng.name}"].latest_version
      autoscaling_group       = aws_autoscaling_group.node_groups["${local.prefix}-${ng.name}"].name
      autoscaling_group_arn   = aws_autoscaling_group.node_groups["${local.prefix}-${ng.name}"].arn
      desired                 = ng.capacity.desired
      min                     = aws_autoscaling_group.node_groups["${local.prefix}-${ng.name}"].min_size
      max                     = aws_autoscaling_group.node_groups["${local.prefix}-${ng.name}"].max_size
      network_interfaces = [
        for ni in aws_launch_template.node_groups["${local.prefix}-${ng.name}"].network_interfaces : {
          network_card_index = ni.network_card_index
          device_index       = ni.device_index
          interface_type     = ni.interface_type
        }
      ]
    }
  }
}

output "system_node_group" {
  value = {
    name           = aws_eks_node_group.system.node_group_name
    arn            = aws_eks_node_group.system.arn
    instance_types = aws_eks_node_group.system.instance_types
    min            = aws_eks_node_group.system.scaling_config[0].min_size
    max            = aws_eks_node_group.system.scaling_config[0].max_size
    status         = aws_eks_node_group.system.status
    ami_type       = aws_eks_node_group.system.ami_type
  }
}

output "addons" {
  value = {
    for name, addon in {
      coreDns                 = aws_eks_addon.coredns
      cloudwatchObservability = aws_eks_addon.cloudwatch_observability
      metricsServer           = aws_eks_addon.metrics_server
      ebsCsiDriver            = aws_eks_addon.ebs_csi_driver
    } : name => { version = addon[0].addon_version, arn = addon[0].arn } if length(addon) > 0
  }
}
