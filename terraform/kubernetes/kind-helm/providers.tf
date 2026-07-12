terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kind" {}

# The helm provider is bound to the kind cluster by referencing its computed
# outputs. In helm v3 the cluster connection is a nested *attribute*
# (`kubernetes = { ... }`), not the v2 `kubernetes { ... }` block.
#
# Those cluster values are unknown until the cluster is applied, so vanilla
# OpenTofu needs two applies (or `-target=kind_cluster.demo`) to get past that;
# Turf's `/up` converges it in one pass via deferrals. See README.
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.demo.endpoint
    client_certificate     = kind_cluster.demo.client_certificate
    client_key             = kind_cluster.demo.client_key
    cluster_ca_certificate = kind_cluster.demo.cluster_ca_certificate
  }
}
