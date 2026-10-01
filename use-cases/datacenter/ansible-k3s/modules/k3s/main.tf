# Ansible's layer: the hosts module.nodes created become a k3s cluster.
#
#   data.ansible_inventory.cluster  the inventory as a value — no file, no
#                                   script. Its hosts' addresses do not exist on
#                                   the first round, so it is read during that
#                                   round's apply, after the hosts.
#   terraform_data.install          the ONE caller. Triggering the playbook from
#                                   the hosts themselves would run it once per
#                                   host; it should run once across them all.
#   ansible_playbook_run.k3s        after_create on the anchor: wait for SSH,
#                                   install k3s with k3s-ansible, fetch the
#                                   kubeconfig back.
#   data.local_sensitive_file       the way back. An action returns nothing
#     .kubeconfig                   Terraform can bind, so the cluster's
#                                   credentials come back as a file.
#   ansible_playbook_run.status     triggered by nothing: run it on demand
#                                   (`turf-driver invoke`, or Terraform's
#                                   `apply -invoke`).

terraform {
  required_providers {
    # Not hashicorp/ansible: a module names a non-HashiCorp source itself.
    ansible = {
      source  = "ansible/ansible"
      version = "1.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

variable "playbook_dir" {
  description = "Absolute path of the playbooks/ directory."
  type        = string
}

variable "k3s_version" {
  description = "k3s release to install."
  type        = string
}

variable "server" {
  description = "The server host, from module.nodes."
  type = object({
    name       = string
    id         = string
    public_ip  = string
    private_ip = string
  })
}

variable "agents" {
  description = "The agent hosts, from module.nodes."
  type = list(object({
    name       = string
    id         = string
    public_ip  = string
    private_ip = string
  }))
}

variable "ssh_user" {
  description = "The login Ansible connects as."
  type        = string
}

variable "ssh_key_file" {
  description = "Absolute path of the SSH private key."
  type        = string
}

variable "kubeconfig_file" {
  description = "Absolute path the playbook fetches the cluster's kubeconfig to."
  type        = string
}

# The cluster's join secret. It travels in the inventory, which the provider
# marks sensitive and hands to ansible-playbook as a file. Not in extra_vars:
# those are passed as `-e key=value` and printed in the action's first line of
# progress.
resource "random_password" "token" {
  length  = 48
  special = false
}

# The shape k3s-ansible expects: k3s_cluster, with server and agent groups
# inside it.
data "ansible_inventory" "cluster" {
  group {
    name = "k3s_cluster"

    vars = {
      k3s_version = var.k3s_version
      token       = random_password.token.result

      # The agents join over the private network. The operator reaches the API
      # over the public address, so the server's certificate must name it too;
      # k3s-ansible adds only api_endpoint by itself.
      api_endpoint       = var.server.private_ip
      server_config_yaml = yamlencode({ "tls-san" = [var.server.private_ip, var.server.public_ip] })

      # k3s-ansible copies a kubeconfig to the control node when kubectl is
      # installed there, and at its default path it merges it into
      # ~/.kube/config. Pointing it here leaves the operator's own kubeconfig
      # alone. The copy Terraform reads is fetched by our own play (site.yml),
      # which does not depend on kubectl being installed.
      kubeconfig     = "${dirname(var.kubeconfig_file)}/k3s-ansible.yaml"
      kubeconfig_out = var.kubeconfig_file
    }

    group {
      name = "server"

      host {
        name                       = var.server.name
        ansible_host               = var.server.public_ip
        ansible_user               = var.ssh_user
        ansible_private_key_file   = var.ssh_key_file
        ansible_python_interpreter = "/usr/bin/python3"
      }
    }

    group {
      name = "agent"

      dynamic "host" {
        for_each = var.agents
        content {
          name                       = host.value.name
          ansible_host               = host.value.public_ip
          ansible_user               = var.ssh_user
          ansible_private_key_file   = var.ssh_key_file
          ansible_python_interpreter = "/usr/bin/python3"
        }
      }
    }
  }
}

# Replaced when any host is, which re-runs the playbook against the new set.
# k3s-ansible's site.yml restarts k3s on every run, so a re-run is a brief
# disruption, not a no-op.
resource "terraform_data" "install" {
  triggers_replace = concat([var.server.id], var.agents[*].id)

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.ansible_playbook_run.k3s]
      # A failed install taints the anchor, so the next run replaces it and
      # runs the playbook again, rather than leaving a created anchor in front
      # of a cluster that was never built.
      on_failure = taint
    }
  }
}

# `playbooks` is a list. The hosts are "running" when AWS says so, which is
# before sshd answers; wait.yml waits for SSH, so site.yml does not race it.
action "ansible_playbook_run" "k3s" {
  config {
    playbooks   = ["${var.playbook_dir}/wait.yml", "${var.playbook_dir}/site.yml"]
    inventories = [data.ansible_inventory.cluster.json]
  }
}

action "ansible_playbook_run" "status" {
  config {
    playbooks   = ["${var.playbook_dir}/status.yml"]
    inventories = [data.ansible_inventory.cluster.json]
  }
}

# The depends_on is load-bearing. On the first round the anchor is still to be
# created, so this read waits for the apply, after the playbook (an after_create
# hook is part of its caller, and what waits on the caller waits on the hook).
# Without it the read would be planned, and a file that does not exist yet is
# an error, not an unknown.
data "local_sensitive_file" "kubeconfig" {
  filename   = var.kubeconfig_file
  depends_on = [terraform_data.install]
}

locals {
  kubeconfig = yamldecode(data.local_sensitive_file.kubeconfig.content)
}

output "cluster_ca_certificate" {
  description = "The cluster's CA, PEM."
  value       = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  sensitive   = true
}

output "client_certificate" {
  description = "The admin client certificate k3s writes, PEM."
  value       = base64decode(local.kubeconfig.users[0].user["client-certificate-data"])
  sensitive   = true
}

output "client_key" {
  description = "The admin client key k3s writes, PEM."
  value       = base64decode(local.kubeconfig.users[0].user["client-key-data"])
  sensitive   = true
}

output "k3s_version" {
  description = "The k3s release the playbook installed."
  value       = var.k3s_version
}
