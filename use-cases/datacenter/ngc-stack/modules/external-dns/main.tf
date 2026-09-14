# ExternalDNS — publishes Service and Ingress hostnames into a DNS zone.
#
# On a real GPU cluster this is what gives a NIMService a resolvable name. Here
# it runs against the `inmemory` provider: the controller, the RBAC and the
# reconcile loop are real, the zone is a map in the pod's memory. That keeps the
# example credential-free while still showing the wiring, and swapping in a real
# provider is a two-variable change.

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

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "external-dns"
}

variable "namespace" {
  description = "Namespace to install into; created if absent"
  type        = string
  default     = "external-dns"
}

variable "chart_version" {
  description = "external-dns/external-dns chart version"
  type        = string
  default     = "1.22.0"
}

variable "dns_provider" {
  description = <<-EOT
    ExternalDNS provider name. `inmemory` is a real controller against a fake
    zone — no credentials, nothing published. Swap for `aws`, `google`,
    `cloudflare`, ... on a cluster that owns a zone, and supply that provider's
    credentials out of band (IRSA, workload identity, a Secret).

    Note the chart's values key is `provider.name`, not `provider`.
  EOT
  type        = string
  default     = "inmemory"
}

variable "policy" {
  description = <<-EOT
    How records are synchronised: create-only, sync, or upsert-only.

    The chart makes this REQUIRED with no default — installing with pure defaults
    fails values-schema validation — so this module always sets it. upsert-only
    is the safe default: it never deletes a record it did not create.
  EOT
  type        = string
  default     = "upsert-only"

  validation {
    condition     = contains(["create-only", "sync", "upsert-only"], var.policy)
    error_message = "policy must be one of: create-only, sync, upsert-only."
  }
}

variable "domain_filters" {
  description = "Zones ExternalDNS is allowed to touch. Empty means all of them."
  type        = list(string)
  default     = []
}

variable "timeout" {
  description = "Seconds helm waits for the release to become Ready"
  type        = number
  default     = 600
}

variable "cluster_endpoint" {
  description = "API endpoint of the containing cluster — see the gpu-operator module for why"
  type        = string
}

resource "null_resource" "cluster" {
  triggers = {
    endpoint = var.cluster_endpoint
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  set = concat(
    [
      { name = "provider.name", value = var.dns_provider },
      { name = "policy", value = var.policy },
    ],
    [
      for i, d in var.domain_filters : {
        name  = "domainFilters[${i}]"
        value = d
      }
    ],
  )

  wait    = true
  timeout = var.timeout

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [null_resource.cluster]
  }
}

output "namespace" {
  description = "Namespace ExternalDNS was installed into"
  value       = helm_release.this.namespace
}

output "chart_version" {
  description = "Chart version actually deployed"
  value       = helm_release.this.metadata.version
}

output "dns_provider" {
  description = "ExternalDNS provider in use"
  value       = var.dns_provider
}
