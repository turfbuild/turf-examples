terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tfcoremock = {
      source  = "hashicorp/tfcoremock"
      version = "0.6.0-beta2"
    }
  }

  # One backend, one state slot per environment: the workspace name selects
  # the slot (terraform.tfstate.d/<name>/ beside this file for every name but
  # "default"). Swap this for an S3/GCS/remote block and the same holds.
  backend "local" {
    path = "terraform.tfstate"
  }
}

# tfcoremock is a mock provider (no real infrastructure, no credentials).
provider "tfcoremock" {
  use_only_state = true
}
