terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  # State is stored in a Kubernetes Secret named "tfstate-{workspace}-demo"
  # in the "turf-state" namespace, with locking via a Coordination Lease.
  #
  # Backend blocks cannot use HCL variables. Configure auth via:
  #   - Environment variables (KUBE_CONFIG_PATH, KUBE_IN_CLUSTER_CONFIG, etc.)
  #   - CLI flags: tofu init -backend-config="config_path=~/.kube/config"
  #   - Editing the literals below
  backend "kubernetes" {
    secret_suffix = "demo"
    namespace     = "turf-state"
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}
