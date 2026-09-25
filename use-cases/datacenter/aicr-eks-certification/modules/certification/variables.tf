variable "cluster_endpoint" {
  description = "Containment key: a new endpoint means a new cluster, so the namespace and the Certification are replaced, not adopted."
  type        = string
}

variable "cluster_version" {
  type = string
}

variable "settings" {
  description = "var.certification from the root (defaults and validation live there)."
  type = object({
    pools         = list(string)
    node_selector = map(string)
    name          = string
    namespace     = string
    categories = list(object({
      domain  = string
      variant = string
      options = map(any)
    }))
    options = map(any)
    taint_selectors = list(object({
      key    = string
      value  = string
      effect = string
    }))
    gang_scheduler = object({
      scheduler_name = string
      queue          = string
    })
    gpus_per_node  = number
    census_timeout = string
    wait_timeout   = string
    settle         = string
    drain_timeout  = string
  })
}

variable "pool_identity" {
  description = "pool name => the launch template version and ASG the nodes came from."
  type = map(object({
    launch_template_id      = string
    launch_template_version = number
    autoscaling_group       = string
  }))
}

variable "expected_nodes" {
  description = "Sum of desired capacity over the certified pools: the census must see exactly this many."
  type        = number
}

variable "stack_revision" {
  description = "Digest of the AICR recipe the stack was generated from."
  type        = string
}
