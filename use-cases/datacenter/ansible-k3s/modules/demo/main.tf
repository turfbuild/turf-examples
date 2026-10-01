# Kubernetes's layer: objects in the cluster Ansible built, through the
# kubernetes provider the root configures from the kubeconfig that came back.
#
# Two rounds after the hosts: the provider cannot be configured until the
# playbook has run, and the custom resource cannot be planned until its CRD is
# served. Both waits are deferrals; nothing here orders them by hand beyond the
# depends_on between the CRD and the object of its kind.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

variable "message" {
  description = "spec.message on the custom resource."
  type        = string
}

variable "namespace" {
  description = "Namespace for the custom resource."
  type        = string
  default     = "default"
}

# What the cluster says about itself: the nodes that registered. Two names here
# are the evidence that the playbook joined the agent, not just started a
# server.
data "kubernetes_nodes" "all" {}

resource "kubernetes_manifest" "crd" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "turfs.demo.local"
    }
    spec = {
      group = "demo.local"
      names = {
        kind     = "Turf"
        plural   = "turfs"
        singular = "turf"
      }
      scope = "Namespaced"
      versions = [
        {
          name    = "v1"
          served  = true
          storage = true
          schema = {
            openAPIV3Schema = {
              type = "object"
              properties = {
                spec = {
                  type = "object"
                  properties = {
                    message = { type = "string" }
                  }
                }
              }
            }
          }
        }
      ]
    }
  }
}

# The Turf kind is not in the cluster's API until the CRD above is applied, so
# this object cannot be planned in the round that creates it. The provider
# defers it, and the next round plans it against an API that now serves the
# kind. Plain Terraform needs a targeted apply of the CRD first.
resource "kubernetes_manifest" "turf" {
  depends_on = [kubernetes_manifest.crd]

  manifest = {
    apiVersion = "demo.local/v1"
    kind       = "Turf"
    metadata = {
      name      = "built-by-ansible"
      namespace = var.namespace
    }
    spec = {
      message = var.message
    }
  }
}

output "node_names" {
  description = "Every node registered with the cluster."
  value       = [for n in data.kubernetes_nodes.all.nodes : n.metadata[0].name]
}

output "crd_name" {
  description = "The CustomResourceDefinition's name."
  value       = kubernetes_manifest.crd.manifest.metadata.name
}

output "cr_name" {
  description = "The custom resource's name."
  value       = kubernetes_manifest.turf.manifest.metadata.name
}

output "cr_message" {
  description = "spec.message on the custom resource."
  value       = kubernetes_manifest.turf.manifest.spec.message
}
