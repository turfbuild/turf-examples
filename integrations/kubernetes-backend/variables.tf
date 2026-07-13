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

variable "app_namespace" {
  description = "Kubernetes namespace for the example workload"
  type        = string
  default     = "kubernetes-backend-example"
}

variable "greeting" {
  description = "Greeting message stored in the ConfigMap"
  type        = string
  default     = "Hello from turf!"
}

variable "environment" {
  description = "Environment label stored in the ConfigMap"
  type        = string
  default     = "demo"
}
