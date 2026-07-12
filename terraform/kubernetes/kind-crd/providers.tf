terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kind" {}

# The kubernetes provider is bound to the kind cluster's computed connection
# details. Those are unknown until the cluster is applied, so plain OpenTofu
# needs two applies (or `-target=kind_cluster.demo`); Turf's `/up` defers and
# converges it in one pass. See README.
provider "kubernetes" {
  host                   = kind_cluster.demo.endpoint
  client_certificate     = kind_cluster.demo.client_certificate
  client_key             = kind_cluster.demo.client_key
  cluster_ca_certificate = kind_cluster.demo.cluster_ca_certificate
}
