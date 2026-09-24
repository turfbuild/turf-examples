provider "aws" {
  region = var.deployment.location

  # Upstream checked the account with a lifecycle precondition on the VPC
  # ("Invalid AWS account (want: …, got: …)"). The provider refuses the wrong
  # account before anything is planned, and needs no engine support for
  # resource conditions.
  allowed_account_ids = [var.deployment.tenancy]

  # Cluster/ManagedBy are upstream's identity tags; its tools/delete-eks sweeper
  # discovers leftovers by them, so they are kept verbatim.
  default_tags {
    tags = merge(var.deployment.tags, {
      Cluster   = var.deployment.id
      ManagedBy = "cluster-toolkit"
    })
  }
}

# Both in-cluster providers are configured from the cluster module's outputs,
# which are unknown until the cluster exists. The engine defers everything that
# uses them (provider_config_unknown) instead of failing the plan.
#
# exec, not a static token: an aws_eks_cluster_auth token lives about 15
# minutes, and the certification wait alone can run 60.
provider "kubernetes" {
  host                   = module.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", var.deployment.location]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", var.deployment.location]
    }
  }
}

# STAND-IN configuration (see versions.tf). The real provider takes the
# kubernetes provider's connection schema:
#
#   provider "kubewait" {
#     host                   = module.eks_cluster.endpoint
#     cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
#     exec {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       command     = "aws"
#       args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
#     }
#   }
provider "kubewait" {
  use_only_state = true
}
