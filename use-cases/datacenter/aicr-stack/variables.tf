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

variable "worker_count" {
  description = <<-EOT
    kind worker nodes beside the control plane. 0 keeps the single-node cluster
    the README measures. kind lifts the control plane's NoSchedule taint only on
    a single-node cluster, so with workers every workload lands on them; 2 is
    the smallest count that lets one be drained (see ../../../terraform/kubernetes/node-maintenance).
  EOT
  type        = number
  default     = 0
}
