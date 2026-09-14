variable "cluster_name" {
  description = "Base name of the kind cluster; the generation suffix is appended"
  type        = string
  default     = "turf-datacenter"
}

variable "generation" {
  description = "Cluster generation; change it to roll the cluster and everything inside it"
  type        = string
  default     = "1"
}

variable "node_image" {
  description = "kind node image (pins the Kubernetes version)"
  type        = string
  default     = "kindest/node:v1.36.1"
}

variable "gpu_operator_version" {
  description = "nvidia/gpu-operator chart version"
  type        = string
  default     = "v26.7.0"
}

variable "nim_operator_version" {
  description = "nvidia/k8s-nim-operator chart version"
  type        = string
  default     = "3.1.2"
}

variable "cert_manager_version" {
  description = "jetstack/cert-manager chart version"
  type        = string
  default     = "v1.21.2"
}

variable "external_dns_version" {
  description = "external-dns/external-dns chart version"
  type        = string
  default     = "1.22.0"
}

variable "enable_admission_controller" {
  description = <<-EOT
    Run the NIM Operator's validating admission webhook — and therefore install
    cert-manager, which is the only reason cert-manager is in this stack. Turn it
    off and the cert-manager module drops out with it.
  EOT
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Install ExternalDNS (against the credential-free inmemory provider)"
  type        = bool
  default     = true
}

variable "dns_provider" {
  description = "ExternalDNS provider; `inmemory` needs no credentials"
  type        = string
  default     = "inmemory"
}

variable "domain_filters" {
  description = "Zones ExternalDNS may touch"
  type        = list(string)
  default     = ["datacenter.local"]
}

variable "gpu_driver_enabled" {
  description = <<-EOT
    Have the GPU Operator deploy the NVIDIA driver DaemonSet. false on kind —
    there is no GPU to drive. See the README's "Pointing this at real GPUs".
  EOT
  type        = bool
  default     = false
}

variable "gpu_toolkit_enabled" {
  description = "Have the GPU Operator deploy the NVIDIA container toolkit DaemonSet"
  type        = bool
  default     = false
}
