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
    # kubewait_condition: waits on the state of Kubernetes objects, attached to
    # lifecycle events. Named here as well as in the modules that use it,
    # because the root module's requirements are what get pre-loaded for the
    # walk. Not on a registry yet — see the README's Prerequisites.
    kubewait = {
      source  = "turfbuild/kubewait"
      version = "~> 0.1"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kind" {}

# Bound to the kind cluster's computed outputs, so every release in the stack is
# unplannable until the cluster exists. Vanilla OpenTofu needs two applies (or
# `-target=kind_cluster.dc`); Turf defers the releases, applies the cluster, and
# re-plans them against the now-known connection — one `turf up`.
#
# The whole stack is helm, including the KAI queues and the pod-grouper's RBAC
# (a local chart, modules/kai-scheduler/queues).
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.dc.endpoint
    client_certificate     = kind_cluster.dc.client_certificate
    client_key             = kind_cluster.dc.client_key
    cluster_ca_certificate = kind_cluster.dc.cluster_ca_certificate
  }
}

# The waits read (get, list, watch) through the same connection as helm. They
# never write.
provider "kubewait" {
  host                   = kind_cluster.dc.endpoint
  client_certificate     = kind_cluster.dc.client_certificate
  client_key             = kind_cluster.dc.client_key
  cluster_ca_certificate = kind_cluster.dc.cluster_ca_certificate
}
