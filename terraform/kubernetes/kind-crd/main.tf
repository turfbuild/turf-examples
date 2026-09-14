# A local Kubernetes cluster running as Docker containers via kind.
#
# The name carries a generation suffix so that a replacement can stand the new
# cluster up BEFORE the old one comes down: kind cluster names are unique, so
# two generations cannot share one. Changing var.generation is what triggers
# the rollover — see "Replacing the cluster" in the README.
#
# There is deliberately no lifecycle block here. The contents below declare
# create_before_destroy, and Turf forces it onto the cluster that holds them —
# declaring it by hand would hide whether that happened.
resource "kind_cluster" "demo" {
  name           = "${var.cluster_name}-${var.generation}"
  node_image     = var.node_image
  wait_for_ready = true
  # kubeconfig_path left unset: the provider manages the kubeconfig and merges a
  # context into your default kubeconfig for `kubectl --context kind-<name>`.
  # A relative kubeconfig_path would be written under the configuration directory
  # — turf runs each provider process with the config dir as its working
  # directory — not your shell's current directory.
}

# A CustomResourceDefinition registering a new API kind, demo.local/v1 Turf.
resource "kubernetes_manifest" "crd" {
  # This object lives INSIDE kind_cluster.demo. Replacing the cluster would
  # annihilate it with no provider RPC at all — no delete in the plan, no chance
  # to run a finalizer — leaving a state entry pointing at nothing. Declaring the
  # containment is what lets the CRD be deleted gracefully through the OLD
  # cluster's endpoint, before the cluster comes down, and re-created afterwards.
  #
  # The containment has to be declared because the graph cannot infer it: a
  # provider whose config merely *references* a resource does not necessarily
  # manage objects that live inside it.
  #
  # Reference the endpoint rather than the bare resource. A bare reference fires
  # on any update to the cluster, so changing an unrelated attribute would tear
  # down the cluster's contents for nothing.
  #
  # create_before_destroy is what keeps the old CRD serving on the old cluster
  # until its replacement exists on the new one, instead of leaving a gap.
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [kind_cluster.demo.endpoint]
  }

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

  # Contained by the cluster, same as the CRD above. Both old objects keep
  # serving until their replacements exist, and the old ones are torn down in
  # reverse dependency — the custom resource before the CRD that defines its
  # kind, which is the order you would use by hand.
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [kind_cluster.demo.endpoint]
  }

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
