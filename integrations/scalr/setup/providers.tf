terraform {
  required_providers {
    scalr = {
      # Resolved from the OpenTofu registry. Scalr also publishes the provider at
      # its own registry — swap the source to "registry.scalr.io/scalr/scalr" if
      # you prefer that.
      source  = "scalr/scalr"
      version = "~> 3.0"
    }
  }

  # This bootstrap config keeps its OWN state local: it is what CREATES the Scalr
  # environment + workspaces the other examples point at, so it can't itself depend
  # on them (chicken-and-egg).
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Auth is out-of-band. The Scalr provider reads its token from the SCALR_TOKEN
# environment variable (or a scalr.io entry in credentials.tfrc.json written by
# `turf login <acct>.scalr.io`). The hostname comes from a variable so the
# account name lives in one place.
provider "scalr" {
  hostname = var.scalr_hostname
}
