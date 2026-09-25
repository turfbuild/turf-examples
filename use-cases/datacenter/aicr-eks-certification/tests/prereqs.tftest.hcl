# modules/cluster-prereqs: the ENIConfigs that replaced upstream's
# `local-exec kubectl apply`, and the vpc-cni add-on that must follow them.

mock_provider "aws" {}
mock_provider "kubernetes" {}

variables {
  prefix       = "tftest"
  cluster_name = "tftest"
  eni_configs = {
    us-west-2a = { subnet_id = "subnet-a", security_group_id = "sg-system" }
    us-west-2b = { subnet_id = "subnet-b", security_group_id = "sg-worker" }
  }
  vpc_cni_version = ""
  networking      = { vpc_cni_minimum_ip_target = 30, vpc_cni_warm_ip_target = 20 }
}

run "eniconfig_manifests_match_upstream_template" {
  command = plan
  module {
    source = "./modules/cluster-prereqs"
  }

  assert {
    condition     = kubernetes_manifest.eniconfig["us-west-2b"].manifest.metadata.name == "us-west-2b"
    error_message = "ENIConfigs are named after the zone (ENI_CONFIG_LABEL_DEF = topology.kubernetes.io/zone)"
  }

  assert {
    condition = (
      kubernetes_manifest.eniconfig["us-west-2b"].manifest.spec.subnet == "subnet-b" &&
      kubernetes_manifest.eniconfig["us-west-2b"].manifest.spec.securityGroups == ["sg-worker"]
    )
    error_message = "spec.subnet and spec.securityGroups carry the zone's subnet and security group"
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 1 && jsondecode(aws_eks_addon.vpc_cni[0].configuration_values).env.AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG == "true"
    error_message = "vpc_cni = \"\" installs vpc-cni with custom networking on"
  }
}

run "no_vpc_cni_no_addon" {
  command = plan
  module {
    source = "./modules/cluster-prereqs"
  }

  variables {
    eni_configs     = {}
    vpc_cni_version = null
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 0 && length(kubernetes_manifest.eniconfig) == 0
    error_message = "no custom networking: neither ENIConfigs nor the managed vpc-cni add-on"
  }
}
