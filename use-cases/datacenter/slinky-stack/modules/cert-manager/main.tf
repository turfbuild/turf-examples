# cert-manager — here because the Slurm operator's webhook asks for it.
#
# slurm-operator runs validating and mutating admission webhooks for every
# Slinky kind, and with its default certManager.enabled=true the chart mints the
# webhook's serving cert by rendering a cert-manager Issuer chain and a
# Certificate. Those are CRDs: if cert-manager is not installed first, the
# operator release fails on unknown kinds. The caller declares that ordering with
# depends_on.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "cert-manager"
}

variable "namespace" {
  description = "Namespace to install into; created if absent"
  type        = string
  default     = "cert-manager"
}

variable "chart_version" {
  description = "jetstack/cert-manager chart version"
  type        = string
  default     = "v1.21.2"
}

variable "install_crds" {
  description = <<-EOT
    Install cert-manager's CRDs as part of the release. Keep true unless they are
    managed separately — with it false, the Certificate the slurm-operator chart
    creates has no kind to be.
  EOT
  type        = bool
  default     = true
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

resource "terraform_data" "cluster" {
  triggers_replace = var.cluster_endpoint
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  # The values key moved from `installCRDs` to `crds.enabled` in v1.15.
  set = [
    { name = "crds.enabled", value = tostring(var.install_crds) },
  ]

  wait    = true
  timeout = var.timeout

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]
  }
}

output "namespace" {
  description = "Namespace cert-manager was installed into"
  value       = helm_release.this.namespace
}

output "chart_version" {
  description = "Chart version actually deployed"
  value       = helm_release.this.metadata.version
}

output "release_id" {
  description = <<-EOT
    The Helm release id (namespace/name). Nothing in this stack consumes it —
    the slurm-operator module orders itself after this one with `depends_on`,
    which needs no value — but it is what a caller would bind if it wanted a
    dependency that also *re-runs* when this release is replaced.
  EOT
  value       = helm_release.this.id
}
