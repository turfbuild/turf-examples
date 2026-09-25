variable "cluster_endpoint" {
  type = string
}

variable "certification_uid" {
  description = "A new certification re-runs the smoke: the smoke is evidence about the certified nodes."
  type        = string
}

variable "settings" {
  description = "var.cuj_train from the root."
  type = object({
    enabled       = bool
    name          = string
    namespace     = string
    num_nodes     = number
    gpus_per_node = number
    image         = string
    runtime       = string
    timeout       = string
  })
}
