variable "cluster_name" {
  description = "kind cluster name; a generation suffix is appended"
  type        = string
  default     = "aicr"
}

variable "generation" {
  description = "Bump to stand up a replacement cluster beside the old one"
  type        = number
  default     = 1
}

variable "node_image" {
  description = "kindest/node image"
  type        = string
  default     = "kindest/node:v1.34.0"
}
