variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use (empty for current context)"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "hpa-example"
}

variable "min_replicas" {
  description = "Minimum number of replicas for the HPA"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of replicas for the HPA"
  type        = number
  default     = 10
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization percentage for the HPA"
  type        = number
  default     = 50
}
