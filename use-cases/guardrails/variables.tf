variable "cluster_name" {
  description = "kind cluster name"
  type        = string
  default     = "turf-guardrails"
}

variable "node_image" {
  description = "kindest/node image"
  type        = string
  default     = "kindest/node:v1.34.0"
}

variable "length" {
  description = "Words in the release's pet name. policies/readable_pet_names.rego denies a plan where this is below 2; the default is the violation, on purpose."
  type        = number
  default     = 1
}

variable "app_ref" {
  description = "The commit of turfbuild/turf-examples the podinfo module is pinned to. Bumping it is an upgrade; init({ upgrade: true }) fetches it."
  type        = string
  default     = "main"
}
