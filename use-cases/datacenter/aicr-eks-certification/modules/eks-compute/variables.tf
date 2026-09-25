# Compute's slice of the typed surface. Defaults and validation live in the root
# variables.tf; cluster, network and IAM facts arrive from ../eks-cluster.

variable "prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  description = "Used to build capacity-reservation resource-group ARNs from bare group names."
  type        = string
}

variable "tags" {
  description = "deployment.tags. Provider default_tags do not reach launch-template tag_specifications, so they are set explicitly (as upstream did)."
  type        = map(string)
}

variable "cluster" {
  type = object({
    name                       = string
    version                    = string
    endpoint                   = string
    certificate_authority_data = string
    service_cidr               = string
  })
}

variable "subnet_ids_by_type" {
  type = map(list(string))
}

variable "system_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = object({
    efa    = string
    worker = string
  })
}

variable "worker_instance_profile_arn" {
  type = string
}

variable "system_node_role" {
  description = "The system node role and the IDs of its policy attachments; the node group must not be created before they exist."
  type = object({
    arn                = string
    policy_attachments = list(string)
  })
}

variable "ssh_public_key" {
  type = string
}

variable "system_pool" {
  type = object({
    instance_type = string
    capacity      = object({ desired = number, min = number, max = number })
    labels        = map(string)
    taints        = list(object({ key = string, value = string, effect = string }))
    block_device  = object({ size = number, type = string })
  })
}

variable "worker_pools" {
  type = map(object({
    instance_type = string
    architecture  = string
    image_id      = string
    accelerator   = string
    labels        = map(string)
    taints        = list(object({ key = string, value = string, effect = string }))
    block_device  = object({ mount = string, size = number, type = string })
    capacity = object({
      desired = number
      min     = number
      max     = number
      reservation = object({
        preference  = string
        target      = string
        market_type = string
      })
    })
  }))
}

variable "autoscaling" {
  type = object({
    capacity_timeout          = string
    delete_timeout            = string
    health_check_grace_period = number
    instance_refresh = object({
      min_healthy_percentage = number
      instance_warmup        = number
      checkpoint_percentages = list(number)
    })
  })
}

variable "metrics_granularity" {
  type = string
}

variable "add_ons" {
  description = "Versions for the add-ons that run as Deployments (null = not installed, \"\" = latest)."
  type = object({
    core_dns                 = string
    cloudwatch_observability = string
    metrics_server           = string
    ebs_csi                  = string
  })
}

variable "addon_role_arns" {
  type = object({
    cloudwatch_observability = string
    ebs_csi                  = string
  })
}
