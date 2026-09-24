# Replaces upstream outputs.tf's `status` output and the local_file status JSON.
# Upstream wrote the full ClusterStatus to a file next to the config, which a
# containerized run (CONFIG_CONTENT) discards with its temp directory; here the
# same facts are module outputs, so they live in state and every consumer (the
# kubernetes/helm providers, the compute module, the root outputs) reads them.

output "prefix" {
  description = "deployment.id — prefixes every resource name."
  value       = local.prefix
}

output "account_id" {
  description = "AWS account the cluster was created in."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  value = local.region
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "endpoint" {
  description = "API server endpoint; the kubernetes and helm providers connect here, and in-cluster modules key their containment shims off it."
  value       = aws_eks_cluster.main.endpoint
}

output "certificate_authority_data" {
  description = "Base64 cluster CA."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "service_cidr" {
  value = aws_eks_cluster.main.kubernetes_network_config[0].service_ipv4_cidr
}

output "oidc" {
  value = {
    issuer       = aws_eks_cluster.main.identity[0].oidc[0].issuer
    provider_arn = aws_iam_openid_connect_provider.oidc_provider.arn
  }
}

output "vpc_cni_enabled" {
  value = local.vpc_cni_enabled
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_ids_by_type" {
  description = "public/system/worker/pod subnet IDs, in config order."
  value       = local.subnet_ids_by_type
}

output "system_subnet_ids" {
  value = local.system_subnet_ids
}

output "security_group_ids" {
  value = {
    cluster = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    system  = aws_security_group.main["${local.prefix}-system"].id
    worker  = aws_security_group.main["${local.prefix}-worker"].id
    efa     = aws_security_group.main["${local.prefix}-efa"].id
    pod     = local.vpc_cni_enabled ? aws_security_group.main["${local.prefix}-pod"].id : null
  }
}

# One ENIConfig per zone for VPC CNI custom networking, built exactly as
# upstream's templates/eni-config.ytpl was: from the SYSTEM and WORKER subnets
# and security groups (not the pod subnets), named after the zone. When a zone
# appears in both tiers the worker entry wins — upstream's template emitted
# system first and `kubectl apply` let the later document overwrite; merge()
# gives the same result deterministically.
output "eni_configs" {
  value = !local.vpc_cni_enabled ? {} : merge(
    {
      for cfg in local.effective_subnets.system : cfg.zone => {
        subnet_id         = aws_subnet.main["${local.prefix}-system-${cfg.zone}"].id
        security_group_id = aws_security_group.main["${local.prefix}-system"].id
      }
    },
    {
      for cfg in local.effective_subnets.worker : cfg.zone => {
        subnet_id         = aws_subnet.main["${local.prefix}-worker-${cfg.zone}"].id
        security_group_id = aws_security_group.main["${local.prefix}-worker"].id
      }
    },
  )
}

# Upstream's system node group depended directly on these attachments ("AWS
# requires IAM policies attached before node group creation"). The node group
# is now in ../eks-compute, so this output carries the role *as attached*: the
# attachment IDs are part of its value, so anything consuming it waits for them.
# (Not `depends_on` on the output: the Restate engine refuses that, tier2.go:115.)
output "system_node_role" {
  value = {
    arn = aws_iam_role.system_nodes.arn
    policy_attachments = [
      aws_iam_role_policy_attachment.system_nodes_policy.id,
      aws_iam_role_policy_attachment.system_nodes_cni_policy.id,
      aws_iam_role_policy_attachment.system_nodes_container_registry_readonly.id,
      aws_iam_role_policy_attachment.system_nodes_ssm_managed_instance_core.id,
      aws_iam_role_policy_attachment.system_nodes_service_role_ebs_csi_driver_policy.id,
    ]
  }
}

output "worker_instance_profile_arn" {
  value = aws_iam_instance_profile.worker_nodes.arn
}

output "addon_role_arns" {
  description = "IRSA roles for the add-ons installed in ../eks-compute."
  value = {
    cloudwatch_observability = aws_iam_role.cloudwatch_observability.arn
    ebs_csi                  = aws_iam_role.ebs_csi_driver.arn
  }
}

# The parts of upstream's ClusterStatus that belong to this module. Compute
# lives in ../eks-compute's outputs; the root composes both.
output "status" {
  value = {
    cluster = {
      name    = aws_eks_cluster.main.name
      version = aws_eks_cluster.main.version
      status  = aws_eks_cluster.main.status
      kubernetes = {
        endpoint = aws_eks_cluster.main.endpoint
        cidr     = aws_eks_cluster.main.kubernetes_network_config[0].service_ipv4_cidr
      }
      oidc = {
        issuer = aws_eks_cluster.main.identity[0].oidc[0].issuer
        arn    = aws_iam_openid_connect_provider.oidc_provider.arn
      }
      addons = {
        kubeProxy = length(aws_eks_addon.kube_proxy) > 0 ? {
          version = aws_eks_addon.kube_proxy[0].addon_version
          arn     = aws_eks_addon.kube_proxy[0].arn
        } : null
      }
    }
    network = {
      vpc = {
        id            = aws_vpc.main.id
        cidr          = aws_vpc.main.cidr_block
        secondaryCidr = local.vpc_cni_enabled ? aws_vpc_ipv4_cidr_block_association.secondary_cidr[0].cidr_block : null
      }
      subnets = {
        for type, group in local.effective_subnets : type => [
          for i, subnet in group : {
            name = "${type}${i + 1}"
            id   = aws_subnet.main["${local.prefix}-${type}-${subnet.zone}"].id
            cidr = subnet.cidr
            zone = subnet.zone
          }
        ]
      }
      natGateways = [
        for i, subnet in local.effective_subnets.public : {
          name             = "nat${i + 1}"
          id               = aws_nat_gateway.main["${local.prefix}-nat-${i}"].id
          publicIp         = aws_eip.nat["${local.prefix}-eip-${i}"].public_ip
          availabilityZone = subnet.zone
        }
      ]
      internetGateway = { id = aws_internet_gateway.main.id }
    }
    iam = {
      roles = {
        cluster     = aws_iam_role.eks_cluster.arn
        systemNodes = aws_iam_role.system_nodes.arn
        workerNodes = aws_iam_role.worker_nodes.arn
        cloudwatch  = aws_iam_role.cloudwatch_observability.arn
        ebsCsi      = aws_iam_role.ebs_csi_driver.arn
        vpcFlowLogs = aws_iam_role.vpc_flow_logs.arn
      }
      instanceProfiles = { workerNodes = aws_iam_instance_profile.worker_nodes.arn }
    }
    security = {
      kms = {
        keyId    = aws_kms_key.eks.id
        keyArn   = aws_kms_key.eks.arn
        aliasArn = aws_kms_alias.eks.arn
      }
      logging = {
        eksClusterLogs   = aws_cloudwatch_log_group.eks_cluster.name
        eksLogsRetention = aws_cloudwatch_log_group.eks_cluster.retention_in_days
        vpcFlowLogs      = aws_cloudwatch_log_group.vpc_flow_logs.name
        vpcFlowRetention = aws_cloudwatch_log_group.vpc_flow_logs.retention_in_days
      }
    }
  }
}
