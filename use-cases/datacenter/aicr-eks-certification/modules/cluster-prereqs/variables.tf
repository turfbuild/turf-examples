variable "prefix" {
  description = "deployment.id, for add-on tags."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "eni_configs" {
  description = "zone => {subnet_id, security_group_id}; empty when VPC CNI custom networking is off."
  type = map(object({
    subnet_id         = string
    security_group_id = string
  }))
}

variable "vpc_cni_version" {
  description = "cluster.add_ons.vpc_cni: null = add-on not installed, \"\" = latest, else a pinned version."
  type        = string
}

variable "networking" {
  description = "networking.vpcCni.{minimumIpTarget,warmIpTarget} upstream."
  type = object({
    vpc_cni_minimum_ip_target = number
    vpc_cni_warm_ip_target    = number
  })
}
