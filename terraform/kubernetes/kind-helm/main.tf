# A local Kubernetes cluster running as Docker containers via kind.
resource "kind_cluster" "demo" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true
  # kubeconfig_path left unset: the provider manages the kubeconfig and merges a
  # context into your default kubeconfig for `kubectl --context kind-<name>`.
  # A relative kubeconfig_path would be written under the configuration directory
  # — turf runs each provider process with the config dir as its working
  # directory — not your shell's current directory.
}

# podinfo — a tiny, reliable demo workload from a public Helm chart repo.
#
# Chosen deliberately over bitnami/nginx: Bitnami sunset its public catalog on
# 2025-08-28 (images moved to docker.io/bitnamilegacy), so bitnami charts now
# leave pods in ImagePullBackOff and helm's wait times out. podinfo's image
# lives on ghcr.io and pulls cleanly, so the release converges in seconds.
resource "helm_release" "podinfo" {
  name       = "podinfo"
  repository = "https://stefanprodan.github.io/podinfo"
  chart      = "podinfo"
  # Empty var → null → latest. Pin a version in tfvars for reproducibility.
  version = var.chart_version != "" ? var.chart_version : null

  namespace        = var.namespace
  create_namespace = true

  # helm_release blocks until every pod/Deployment is Ready (wait = true), or
  # fails when the timeout expires. We shorten the timeout so a broken chart
  # surfaces fast instead of hanging.
  wait    = true
  timeout = 120

  # The release lives INSIDE kind_cluster.demo. Replacing the cluster would
  # annihilate it with no provider RPC at all — helm would never run its
  # uninstall, no hooks would fire — leaving a state entry pointing at nothing.
  # Declaring the containment is what lets the release be uninstalled gracefully
  # through the OLD cluster's endpoint, before the cluster comes down, and
  # re-installed afterwards.
  #
  # The containment has to be declared because the graph cannot infer it: a
  # provider whose config merely *references* a resource does not necessarily
  # manage objects that live inside it.
  #
  # Reference the endpoint rather than the bare resource. A bare reference fires
  # on any update to the cluster, so changing an unrelated attribute would
  # uninstall the release for nothing.
  lifecycle {
    replace_triggered_by = [kind_cluster.demo.endpoint]
  }
}
