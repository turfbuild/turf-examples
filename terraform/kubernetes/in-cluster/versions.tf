# No backend block: this configuration is published as an image and run
# read-only, so the deployment that runs it names the backend when it opens a
# workspace (a local statefile could not be written beside it anyway).
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}
