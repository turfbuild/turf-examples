variable "cluster_name" {
  description = "Name of the kind cluster"
  type        = string
  default     = "turf-helm-demo"
}

variable "node_image" {
  description = "kind node image (pins the Kubernetes version)"
  type        = string
  default     = "kindest/node:v1.29.7"
}

variable "namespace" {
  description = "Namespace for the Helm release"
  type        = string
  default     = "podinfo"
}

variable "chart_version" {
  description = "podinfo chart version to install (empty string = latest)"
  type        = string
  default     = ""
}
