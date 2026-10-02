# Slinky's slurm-operator — the controller that turns Slurm into Kubernetes
# objects.
#
# Six CRDs (Controller, NodeSet, LoginSet, RestApi, Accounting, Token under
# slinky.slurm.net/v1beta1) and the operator that reconciles them: a Controller
# becomes a slurmctld StatefulSet, a NodeSet becomes slurmd pods that register
# themselves with it as dynamic Slurm nodes, a LoginSet becomes sackd + sshd.
#
# Two releases, in the order upstream documents: the CRDs on their own, then the
# operator. The operator chart can carry the CRDs as a subchart
# (crds.enabled=true), but keeping them separate means the CRDs — and so every
# Slurm cluster's objects — outlive an operator reinstall.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

variable "namespace" {
  description = "Namespace the operator and its webhook run in; created if absent"
  type        = string
  default     = "slinky"
}

variable "chart_version" {
  description = "slurm-operator and slurm-operator-crds chart version (they are released together)"
  type        = string
  default     = "1.2.2"
}

variable "cert_manager_enabled" {
  description = <<-EOT
    Have cert-manager mint the webhook's serving certificate. With it false the
    chart generates one itself at render time (and reuses it on upgrade via a
    lookup); the caller then needs no cert-manager at all.
  EOT
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Seconds helm waits for each release to become Ready"
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

locals {
  repository = "oci://ghcr.io/slinkyproject/charts"
}

# Cluster-scoped: the CRDs have no namespace, so the release's namespace is only
# where helm keeps its record of them.
resource "helm_release" "crds" {
  name       = "slurm-operator-crds"
  repository = local.repository
  chart      = "slurm-operator-crds"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  wait    = true
  timeout = var.timeout

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]
  }
}

# The operator and its webhook.
#
# wait = true is load-bearing here, which is rare: the validating webhook is
# registered with failurePolicy Fail for every Slinky kind, so until the webhook
# pod is serving, any Controller or NodeSet the caller creates is *rejected*
# rather than merely unreconciled. Waiting on this release's Deployments is what
# makes depends_on on this module mean "safe to create Slurm objects".
resource "helm_release" "operator" {
  name       = "slurm-operator"
  repository = local.repository
  chart      = "slurm-operator"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  set = [
    { name = "certManager.enabled", value = tostring(var.cert_manager_enabled) },
  ]

  wait    = true
  timeout = var.timeout

  depends_on = [helm_release.crds]

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]
  }
}

output "namespace" {
  description = "Namespace the operator was installed into"
  value       = helm_release.operator.namespace
}

output "chart_version" {
  description = "Chart version actually deployed"
  value       = helm_release.operator.metadata.version
}

output "crd_kinds" {
  description = "The custom resource kinds this operator reconciles (slinky.slurm.net/v1beta1)"
  value       = ["Controller", "NodeSet", "LoginSet", "RestApi", "Accounting", "Token"]
}
