# The root owns the providers. bundle/ is a child module and inherits the helm
# provider configured here — which is the only way to point a generated bundle
# at a cluster this same configuration creates.
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

# Bound to the cluster's computed attributes, so the provider configuration is
# unknown until the cluster is applied. That is the point of the example: every
# release in bundle/ is unplannable on the first walk.
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.dc.endpoint
    client_certificate     = kind_cluster.dc.client_certificate
    client_key             = kind_cluster.dc.client_key
    cluster_ca_certificate = kind_cluster.dc.cluster_ca_certificate
  }
}
