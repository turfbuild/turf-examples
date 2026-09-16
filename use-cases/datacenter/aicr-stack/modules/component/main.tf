# One AICR component: a single Helm release, contained by the cluster it runs on.
#
# Generic on purpose. An AICR component is fully described by (chart, repo,
# version, namespace, values) — the bundler wraps even manifest-only components
# as local charts — so every component in the recipe is this module with
# different arguments.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

variable "release_name" { type = string }
variable "namespace" { type = string }
variable "chart" { type = string }

variable "repository" {
  description = "Chart repository URL; empty for OCI charts and local chart directories"
  type        = string
  default     = ""
}

variable "chart_version" {
  description = "Chart version; empty for local charts, which carry their own"
  type        = string
  default     = ""
}

variable "values_file" { type = string }

variable "wait" {
  description = "Block until the release's workloads report Ready"
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Seconds helm waits"
  type        = number
  default     = 900
}

variable "cluster_endpoint" {
  description = <<-EOT
    API endpoint of the containing cluster. Nothing here reads it — it exists so
    the release is *contained* by the cluster: replace the cluster and every
    release in it is replaced too, rather than being adopted by a new cluster
    that has never seen it.
  EOT
  type        = string
}

resource "null_resource" "cluster" {
  triggers = {
    endpoint = var.cluster_endpoint
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  chart      = var.chart
  repository = var.repository != "" ? var.repository : null
  version    = var.chart_version != "" ? var.chart_version : null

  namespace        = var.namespace
  create_namespace = true

  values = [file(var.values_file)]

  wait    = var.wait
  timeout = var.timeout

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [null_resource.cluster]
  }
}

output "release_id" {
  description = "namespace/name of the Helm release"
  value       = helm_release.this.id
}
