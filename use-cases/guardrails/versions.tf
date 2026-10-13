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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kind" {}

# Bound to the cluster's computed attributes, so the release defers to the
# round after the cluster exists.
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.demo.endpoint
    client_certificate     = kind_cluster.demo.client_certificate
    client_key             = kind_cluster.demo.client_key
    cluster_ca_certificate = kind_cluster.demo.cluster_ca_certificate
  }
}
