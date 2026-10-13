variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use (empty for the current context); kind-<cluster> for a kind cluster"
  type        = string
  default     = ""
}

variable "maintenance" {
  description = "Nodes held in maintenance: cordoned, drained, repaired, re-certified. Remove a node to uncordon it."
  type        = set(string)
  default     = []
}

variable "drain_flags" {
  description = "Flags for kubectl drain"
  type        = list(string)
  default     = ["--ignore-daemonsets", "--delete-emptydir-data", "--timeout=10m"]
}
