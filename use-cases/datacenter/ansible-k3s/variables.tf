variable "aws_region" {
  description = "AWS region for the hosts and their network."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix for every AWS resource's Name tag and the key pair's name."
  type        = string
  default     = "turf-k3s"
}

variable "instance_type" {
  description = "EC2 instance type for every host. k3s wants about 2 GiB on the server."
  type        = string
  default     = "t3.small"
}

variable "agent_count" {
  description = <<-EOT
    k3s agents beside the one server. Changing it replaces the install anchor,
    which runs the playbook again across the new set of hosts.
  EOT
  type        = number
  default     = 1
}

variable "k3s_version" {
  description = <<-EOT
    k3s release to install. k3s-ansible has no default for it and uses it
    unguarded, so it is always rendered into the inventory.
  EOT
  type        = string
  default     = "v1.36.4+k3s1"
}

variable "operator_cidr" {
  description = <<-EOT
    The only network allowed to reach the hosts on 22 (Ansible) and 6443 (the
    kubernetes provider). Null means this machine's public address, looked up
    from checkip.amazonaws.com, as a /32.
  EOT
  type        = string
  default     = null
}

variable "message" {
  description = "spec.message on the custom resource the last round creates."
  type        = string
  default     = "Hosts by Terraform, k3s by Ansible, this object by Terraform again."
}
