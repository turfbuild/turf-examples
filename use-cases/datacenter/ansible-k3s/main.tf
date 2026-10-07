# Bare Linux hosts, configured into a Kubernetes cluster by Ansible, with
# objects applied to that cluster — one configuration, three tools, one graph.
#
#   module.nodes  Terraform: a VPC, a security group, an SSH key and two
#                 Ubuntu hosts. Nothing on them is configured.
#   module.k3s    Ansible: the inventory as a value, ONE playbook run that
#                 installs k3s across both hosts, and the cluster's kubeconfig
#                 fetched back to a file Terraform reads.
#   module.demo   Kubernetes: a CRD and an object of its kind, through a
#                 provider configured from that file.
#
# Each layer cannot be planned until the one before it has been applied: the
# hosts have no addresses, the cluster has no credentials, the custom kind is not
# served. Turf's deferral loop plans what it can each round and comes back for
# the rest. See README.md for the rounds as measured.

locals {
  # Files this configuration writes and reads outside of state: the SSH key
  # Ansible connects with and the kubeconfig the playbook fetches back. Absolute,
  # because Ansible resolves them, and one directory so cleanup is one rm.
  local_dir = abspath("${path.root}/.k3s")

  # Ansible is the one path into the hosts, and the kubernetes provider the one
  # path into the cluster; both come from this machine. The lookup exists only
  # when operator_cidr is unset (its count is the gate), so the other branch is
  # never evaluated — a conditional, not coalesce(), which evaluates every
  # argument and trips over trimspace(null) when the count is 0.
  operator_cidr = (
    var.operator_cidr != null
    ? var.operator_cidr
    : "${trimspace(one(data.http.operator_ip[*].response_body))}/32"
  )
}

# Looked up only when operator_cidr is unset.
data "http" "operator_ip" {
  count = var.operator_cidr == null ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

module "nodes" {
  source = "./modules/nodes"

  name_prefix   = var.name_prefix
  instance_type = var.instance_type
  agent_count   = var.agent_count
  operator_cidr = local.operator_cidr
  key_file      = "${local.local_dir}/id_ed25519"
}

module "k3s" {
  source = "./modules/k3s"

  # The provider runs ansible-playbook in this configuration's directory, so
  # the ansible.cfg and collections/ beside this file are the ones it uses.
  playbook_dir = abspath("${path.root}/playbooks")

  k3s_version     = var.k3s_version
  server          = module.nodes.server
  agents          = module.nodes.agents
  ssh_user        = module.nodes.ssh_user
  ssh_key_file    = module.nodes.key_file
  kubeconfig_file = "${local.local_dir}/k3s.yaml"
}

module "demo" {
  source = "./modules/demo"

  message = var.message
}
