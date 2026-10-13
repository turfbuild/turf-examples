variable "name" {
  description = "Release name"
  type        = string
  default     = "podinfo"
}

variable "namespace" {
  description = "Namespace for the release"
  type        = string
  default     = "podinfo"
}

variable "chart_version" {
  description = "podinfo chart version (empty = latest)"
  type        = string
  default     = ""
}

variable "cluster_endpoint" {
  description = "The endpoint of the cluster the caller's helm provider targets; a change replaces the release"
  type        = string
}
