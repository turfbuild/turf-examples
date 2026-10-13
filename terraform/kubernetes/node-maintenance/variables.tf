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

variable "node" {
  description = "The node this configuration maintains. One node, named once: the steps reference their node by a constant (see README, On Turf)."
  type        = string
}

variable "maintenance" {
  description = "The node, when it is held in maintenance: cordoned, drained, repaired, re-certified. Empty it to uncordon."
  type        = set(string)
  default     = []

  validation {
    condition     = length(setsubtract(var.maintenance, [var.node])) == 0
    error_message = "maintenance may only name var.node; this configuration maintains one node."
  }
}

variable "drain_flags" {
  description = "Flags for kubectl drain"
  type        = list(string)
  default     = ["--ignore-daemonsets", "--delete-emptydir-data", "--timeout=10m"]
}
