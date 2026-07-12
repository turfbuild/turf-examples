variable "cluster_name" {
  description = "Name of the kind cluster"
  type        = string
  default     = "turf-crd-demo"
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
