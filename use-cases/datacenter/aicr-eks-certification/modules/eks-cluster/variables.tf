# The cluster's slice of the typed surface. Defaults and validation live in the
# root variables.tf, which passes these objects through fully defaulted; the
# types here are the module's contract. Upstream read the same values from
# yamldecode(file(var.CONFIG_PATH)) with try() fallbacks.

variable "deployment" {
  description = "deployment.{id,tenancy,location} — naming prefix, AWS account, region."
  type = object({
    id       = string
    tenancy  = string
    location = string
  })
}

variable "cluster" {
  description = "EKS control plane: version, name, admin roles, CIDRs, add-on versions."
  type = object({
    version       = string
    name          = string
    admin_roles   = list(string)
    service_cidr  = string
    allowed_cidrs = list(string)
    add_ons = object({
      core_dns                 = string
      vpc_cni                  = string
      kube_proxy               = string
      cloudwatch_observability = string
      metrics_server           = string
      ebs_csi                  = string
    })
  })
}

variable "network" {
  description = "VPC CIDRs, subnets (null = derived from the first two AZs), endpoints, extra SG rules."
  type = object({
    host_cidr = string
    pod_cidr  = string
    subnets = object({
      public = list(object({ cidr = string, zone = string }))
      system = list(object({ cidr = string, zone = string }))
      worker = list(object({ cidr = string, zone = string }))
      pod    = list(object({ cidr = string, zone = string }))
    })
    endpoints = list(string)
    additional_rules = list(object({
      target      = string
      direction   = string
      description = string
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = list(string)
    }))
  })
}

variable "iam" {
  description = "Extra managed-policy ARNs attached to the system and worker node roles."
  type = object({
    system_node_policies = list(string)
    worker_node_policies = list(string)
  })
}

variable "observability" {
  description = "Log retention for the control plane and VPC flow logs."
  type = object({
    log_retention_days          = number
    vpc_flow_log_retention_days = number
  })
}

variable "security" {
  description = "KMS key deletion window."
  type = object({
    kms_deletion_window_days = number
  })
}
