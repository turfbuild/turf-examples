variable "namespace" {
  description = "Namespace the greeting is written to; created by this configuration."
  type        = string
  default     = "turf-greeting"
}

variable "greeting" {
  description = "The text the ConfigMap holds."
  type        = string
  default     = "Hello from a configuration image."
}

variable "kubeconfig_path" {
  description = "Kubeconfig to reach the cluster with. Empty: the in-cluster service account."
  type        = string
  default     = ""
}
