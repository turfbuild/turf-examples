# A local Kubernetes cluster running as Docker containers via kind.
resource "kind_cluster" "demo" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true
  # kubeconfig_path left unset: the provider manages the kubeconfig and merges a
  # context into your default kubeconfig for `kubectl --context kind-<name>`.
}

# A CustomResourceDefinition registering a new API kind, demo.local/v1 Turf.
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

# A custom resource — an instance of the kind the CRD above registers.
#
# The Turf kind does not exist in the cluster's API until the CRD is applied, so
# this manifest cannot be planned until then. depends_on orders it after the CRD;
# Turf additionally defers it to a later phase (and reloads the provider so it
# re-discovers the new API) to converge CRD-then-CR in a single `/up`. Plain
# OpenTofu needs a targeted apply of the CRD first.
resource "kubernetes_manifest" "instance" {
  depends_on = [kubernetes_manifest.crd]

  manifest = {
    apiVersion = "demo.local/v1"
    kind       = "Turf"
    metadata = {
      name      = "example-turf"
      namespace = var.namespace
    }
    spec = {
      message = var.cr_message
    }
  }
}
