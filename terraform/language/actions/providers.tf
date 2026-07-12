terraform {
  required_providers {
    tfcoremock = {
      source  = "hashicorp/tfcoremock"
      version = "0.6.0-beta2"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# tfcoremock is a mock provider (no real infrastructure, no credentials). Its
# 0.6.0-beta2 release is the first to ship Terraform 1.14 *actions*, and it's
# resolvable straight from the public registry. use_only_state avoids file I/O.
provider "tfcoremock" {
  use_only_state = true
}
