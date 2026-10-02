# NVIDIA GPU Operator — what makes a Kubernetes node a GPU node.
#
# The operator manages the driver, container toolkit, device plugin and DCGM
# exporter on GPU nodes. The device plugin is what advertises nvidia.com/gpu,
# the resource the Slurm GPU NodeSet asks for; DCGM exporter is what turns GPU
# telemetry into metrics, labelled with Slurm job IDs when HPC job mapping is on.
#
# On a node with no NVIDIA device it manages nothing: the bundled Node Feature
# Discovery finds no PCI vendor 10de, so the operand DaemonSets are never
# created at all — not created-with-zero-replicas, absent. The ClusterPolicy
# still reports Ready, with reason NoGPUNodes.
#
# That is why this module is safe to run on a laptop, and why it is worth doing:
# the control plane is identical to the one a GPU cluster runs.

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

variable "hpc_job_mapping_dir" {
  description = <<-EOT
    Host directory DCGM exporter reads to label GPU metrics with the HPC job that
    holds each GPU. Slurm's prolog writes one file per GPU there and its epilog
    removes it — so this path is a contract between two vendors' charts, and
    the caller passes the same value to the Slurm side through this module's
    output. null leaves HPC job mapping off.
  EOT
  type        = string
  default     = null
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
    terraform_data below.
  EOT
  type        = string
}

# A module cannot name a resource in its caller, and replace_triggered_by only
# accepts references within the same module. This carries the containment across
# the module boundary: the caller passes the cluster's endpoint in, and this
# resource turns it into something the release can point at. A new cluster has a
# new endpoint, so this is replaced, and the release with it — uninstalled
# through the OLD endpoint first.
resource "terraform_data" "cluster" {
  triggers_replace = var.cluster_endpoint
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  set = concat(
    [
      { name = "driver.enabled", value = tostring(var.driver_enabled) },
      { name = "toolkit.enabled", value = tostring(var.toolkit_enabled) },
      { name = "nfd.enabled", value = tostring(var.nfd_enabled) },
    ],
    var.hpc_job_mapping_dir == null ? [] : [
      { name = "dcgmExporter.hpcJobMapping.enabled", value = "true" },
      { name = "dcgmExporter.hpcJobMapping.directory", value = var.hpc_job_mapping_dir },
    ],
  )

  wait    = true
  timeout = var.timeout

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.cluster]
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

output "gpu_resource" {
  description = <<-EOT
    The extended resource the device plugin advertises. No node carries it until
    the operator has found a GPU and deployed the plugin there, so anything that
    requests it — a Slurm GPU NodeSet, say — pends until then.
  EOT
  value       = "nvidia.com/gpu"
}

output "dcgm_job_mapping_dir" {
  description = <<-EOT
    The HPC job-mapping directory DCGM exporter was configured to read, or null.
    Read back from the release's own settings rather than from the variable, so
    that a consumer binding it is ordered after the operator: a value edge, not
    just an order-only one.
  EOT
  value       = one([for s in helm_release.this.set : s.value if s.name == "dcgmExporter.hpcJobMapping.directory"])
}
