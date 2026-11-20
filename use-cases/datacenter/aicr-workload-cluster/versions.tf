# The root owns the provider. ../aicr-stack/bundle is a child module and
# inherits the helm provider configured here: the same generated bundle the
# kind example installs, pointed at a cluster that already exists.
#
# No backend block: whoever runs this names one when it opens a workspace
# (README, "Configuration images"), so it runs from a read-only mount.
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

# The cluster's credentials are a kubeconfig file where Turf's engine runs,
# and nowhere else: not in this configuration, not in the state, and not with
# the agent that asks for the plan.
provider "helm" {
  kubernetes = {
    config_path = local.kubeconfig
  }
}
