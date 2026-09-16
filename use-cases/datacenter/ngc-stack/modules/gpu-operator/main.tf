# NVIDIA GPU Operator — the cluster-side half of NVIDIA GPU Cloud.
#
# The operator manages the driver, container toolkit, device plugin and DCGM
# exporter on GPU nodes. On a node with no NVIDIA device it manages nothing: the
# bundled Node Feature Discovery finds no PCI vendor 10de, so the operand
# DaemonSets are never created at all — not created-with-zero-replicas, absent.
# The ClusterPolicy still reports Ready, with reason NoGPUNodes.
#
# That is why this module is safe to run on a laptop, and why it is worth doing:
# the control plane is identical to the one a GPU cluster runs.

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
  default     = "gpu-operator"
}

variable "namespace" {
  description = "Namespace to install into; created if absent"
  type        = string
  default     = "gpu-operator"
}

variable "chart_version" {
  description = "nvidia/gpu-operator chart version"
  type        = string
  default     = "v26.7.0"
}

variable "driver_enabled" {
  description = <<-EOT
    Deploy the NVIDIA driver DaemonSet. false is correct wherever the driver is
    already on the host (and on any cluster with no GPU at all, where there is
    nothing to install a driver onto). Set true on a node pool whose image ships
    no driver — and note the chart then requires every GPU node to run the same
    OS version.
  EOT
  type        = bool
  default     = false
}

variable "toolkit_enabled" {
  description = <<-EOT
    Deploy the NVIDIA container toolkit DaemonSet. Same reasoning as
    driver_enabled: false where the runtime is already configured, true on a
    stock node pool.
  EOT
  type        = bool
  default     = false
}

variable "nfd_enabled" {
  description = <<-EOT
    Let this chart deploy Node Feature Discovery. Set false only when NFD is
    already running in the cluster — two NFD masters will fight over node labels.
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
  description = <<-EOT
    The API endpoint of the cluster this release lives inside. Not used to
    connect — the provider already carries the connection — but to declare
    containment, so that replacing the cluster uninstalls the release through the
    OLD endpoint first instead of annihilating it with no provider RPC. See the
    null_resource below.
  EOT
  type        = string
}

# A module cannot name a resource in its caller, and replace_triggered_by only
# accepts references within the same module. This carries the containment across
# the module boundary: the caller passes the cluster's endpoint in, and this
# resource turns it into something the release can point at.
#
# null_resource and not the built-in terraform_data, which would be the modern
# spelling: Turf does not serve the built-in "terraform" provider, so a
# terraform_data here fails the walk with "provider \"terraform\" is not a
# required provider of this workspace".
resource "null_resource" "cluster" {
  triggers = {
    endpoint = var.cluster_endpoint
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  set = [
    { name = "driver.enabled", value = tostring(var.driver_enabled) },
    { name = "toolkit.enabled", value = tostring(var.toolkit_enabled) },
    { name = "nfd.enabled", value = tostring(var.nfd_enabled) },
  ]

  wait    = true
  timeout = var.timeout

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

output "gpu_node_label" {
  description = <<-EOT
    The Node Feature Discovery label that gates every GPU operand — and, not
    coincidentally, the nodeSelector the NIM Operator puts on its model-puller
    pods. 10de is NVIDIA's PCI vendor ID.
  EOT
  value       = "feature.node.kubernetes.io/pci-10de.present=true"
}

output "release_id" {
  description = <<-EOT
    The Helm release id (namespace/name). Nothing in this stack consumes it —
    the NIM module orders itself after this one with `depends_on`, which needs
    no value — but it is what a caller would bind if it wanted a dependency
    that also *re-runs* when this release is replaced.
  EOT
  value       = helm_release.this.id
}
