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
    # Reached only from the child modules, where it carries the containment
    # declaration. Named here because the root module's requirements are what get
    # pre-loaded for the walk.
    null = {
      source  = "hashicorp/null"
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
# None of those values exist until the cluster is applied, so every module in
# this stack is unplannable on the first walk. Vanilla OpenTofu needs two applies
# (or `-target=kind_cluster.dc`); Turf defers the four releases, applies the
# cluster, and re-plans them against the now-known connection — one `turf up`.
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.dc.endpoint
    client_certificate     = kind_cluster.dc.client_certificate
    client_key             = kind_cluster.dc.client_key
    cluster_ca_certificate = kind_cluster.dc.cluster_ca_certificate
  }
}
