# podinfo — a tiny, reliable demo workload from a public Helm chart repo — as a
# child module: no provider block, so a root that configures `helm` against a
# cluster it creates can call this at a pinned ref and inherit it.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

resource "helm_release" "podinfo" {
  name       = var.name
  repository = "https://stefanprodan.github.io/podinfo"
  chart      = "podinfo"
  version    = var.chart_version != "" ? var.chart_version : null

  namespace        = var.namespace
  create_namespace = true

  wait    = true
  timeout = 120

  # The release lives inside the cluster the caller configured helm against.
  # Replacing that cluster must replace the release, not orphan it; the caller
  # passes something that changes with the cluster (its endpoint).
  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]
  }
}

resource "terraform_data" "cluster" {
  triggers_replace = var.cluster_endpoint
}
