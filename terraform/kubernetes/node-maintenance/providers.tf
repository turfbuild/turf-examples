terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3"
    }
    # The wait. kubewait is published on registry.terraform.io only, and Turf
    # resolves a bare source against registry.opentofu.org, so the host is
    # spelled out. Terraform reads it as the same address.
    kubewait = {
      source  = "registry.terraform.io/turfbuild/kubewait"
      version = "~> 0.1"
    }
    # local_command runs kubectl for the steps that change a node.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "kubewait" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}
