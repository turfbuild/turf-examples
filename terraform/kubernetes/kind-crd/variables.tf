variable "cluster_name" {
  description = "Base name of the kind cluster; the generation suffix is appended"
  type        = string
  default     = "turf-crd-demo"
}

variable "generation" {
  description = "Cluster generation; change it to roll the cluster and everything inside it"
  type        = string
  default     = "1"
}

variable "node_image" {
  description = "kind node image (pins the Kubernetes version)"
  type        = string
  default     = "kindest/node:v1.29.7"
}

variable "namespace" {
  description = "Namespace for the custom resource instance"
  type        = string
  default     = "default"
}

variable "cr_message" {
  description = "spec.message on the example Turf custom resource"
  type        = string
  default     = "Hello from Turf"
}
