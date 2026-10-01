terraform {
  required_providers {
    # Turf installs from registry.opentofu.org, which publishes
    # hashicorp/aws a release or so behind registry.terraform.io.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    # ansible/ansible serves plugin protocol 5 only (an SDKv2 server and a
    # framework server behind one mux). Pinned exactly: the README's notes on
    # the action's output describe this release.
    ansible = {
      source  = "ansible/ansible"
      version = "1.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    # Reached only from the child modules. Named here because the root module's
    # requirements are what get pre-loaded for the walk.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      "turf.build/example" = "ansible-k3s"
      "turf.build/prefix"  = var.name_prefix
    }
  }
}

# The cluster this provider talks to does not exist until Ansible has built it,
# and its credentials exist only as a file the playbook fetches back. So the
# address comes from Terraform (the server's public IP) and the credentials come
# from that file, read by module.k3s.
#
# On the first round none of the credentials are known: the file is read during
# the apply, after the playbook. Everything in module.demo therefore defers with
# provider_config_unknown and is planned on the next round, against a cluster
# that is now there. Plain Terraform needs a targeted apply here instead; see the
# README.
provider "kubernetes" {
  host                   = "https://${module.nodes.server_public_ip}:6443"
  cluster_ca_certificate = module.k3s.cluster_ca_certificate
  client_certificate     = module.k3s.client_certificate
  client_key             = module.k3s.client_key
}
