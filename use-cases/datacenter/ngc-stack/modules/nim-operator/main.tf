# NVIDIA NIM Operator — the CRD controller for NIM microservices and NeMo
# services (NIMCache, NIMService, NIMPipeline, NIMBuild, NemoEvaluator, ...).
#
# NVIDIA documents the GPU Operator as a prerequisite. That is true of *CR
# reconciliation*, not of the controller: this deployment requests no GPU, sets
# no nodeSelector, and its image pulls anonymously from nvcr.io with no
# imagePullSecret. It reaches Ready on a cluster that has never seen a GPU.
#
# The GPU requirement reappears the moment you create a NIMCache: the operator
# builds a model-puller pod whose nodeSelector is
# feature.node.kubernetes.io/pci-10de.present=true — the same label the GPU
# Operator is waiting for. See the stack README.

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
  default     = "nim-operator"
}

variable "namespace" {
  description = "Namespace to install into; created if absent"
  type        = string
  default     = "nim-operator"
}

variable "chart_version" {
  description = "nvidia/k8s-nim-operator chart version"
  type        = string
  default     = "3.1.2"
}

variable "admission_controller_enabled" {
  description = <<-EOT
    Run the validating admission webhook for NIMCache and NIMService.

    This is what makes cert-manager a real dependency rather than a decoration:
    the chart's own values.yaml says "cert-manager must be installed beforehand,
    as it is required to generate the TLS certificates". With it off, malformed
    CRs are caught only by CRD schema validation, which cannot express
    cross-field rules.
  EOT
  type        = bool
  default     = true
}

variable "image_pull_secret" {
  description = <<-EOT
    Name of an imagePullSecret for the operator image. Leave empty: the operator
    image (nvcr.io/nvidia/cloud-native/k8s-nim-operator) pulls anonymously. An
    NGC key is needed for the *model* images a NIMCache pulls, which is a
    different secret, referenced from the CR rather than from this chart.
  EOT
  type        = string
  default     = ""
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

variable "upstream" {
  description = <<-EOT
    Release ids this operator must be installed after. Pass
    `module.cert_manager[0].release_id` — the chart renders a cert-manager
    Issuer and Certificate, so those CRDs must already exist — and
    `module.gpu_operator.release_id`, which is the soft half of the ordering.

    Referencing them from the release rather than naming them in a
    `depends_on` is deliberate twice over: Turf's Restate engine refuses
    `depends_on` on a module call, and a re-created cert-manager genuinely
    should re-run this release, because the webhook's serving certificate and
    the caBundle injected into the webhook configuration are re-minted with it.
  EOT
  type        = list(string)
  default     = []
}

resource "null_resource" "cluster" {
  triggers = {
    endpoint = var.cluster_endpoint
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "k8s-nim-operator"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  set = concat(
    [
      {
        name  = "operator.admissionController.enabled"
        value = tostring(var.admission_controller_enabled)
      },
    ],
    var.image_pull_secret == "" ? [] : [
      {
        name  = "operator.image.pullSecrets[0]"
        value = var.image_pull_secret
      },
    ],
  )

  wait    = true
  timeout = var.timeout

  # Recording the upstream releases in the Helm release description is what
  # creates the dependency edge — a reference, not a depends_on. It has to land
  # on the release rather than on null_resource.cluster above: the upstream
  # releases are themselves deferred until the cluster exists, and Turf's
  # Restate engine will not apply a resource that is ordered after a deferred
  # one. Both releases deferred, both converge in the same later phase.
  #
  # It is also just true, and `helm list` shows it.
  description = "NVIDIA NIM Operator${length(var.upstream) == 0 ? "" : " — installed after ${join(", ", var.upstream)}"}"

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [null_resource.cluster]
  }
}

output "namespace" {
  description = "Namespace the operator was installed into"
  value       = helm_release.this.namespace
}

output "chart_version" {
  description = "Chart version actually deployed"
  value       = helm_release.this.metadata.version
}

output "crd_kinds" {
  description = "The custom resource kinds this operator installs and reconciles"
  value = [
    "NIMCache", "NIMService", "NIMPipeline", "NIMBuild",
    "NemoCustomizer", "NemoDatastore", "NemoEntitystore",
    "NemoEvaluator", "NemoGuardrail",
  ]
}
