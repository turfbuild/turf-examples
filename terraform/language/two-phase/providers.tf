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

# tfcoremock stands in for a device/API here so the example stays credential-free
# and runs against the public registry. use_only_state avoids file I/O.
provider "tfcoremock" {
  use_only_state = true
}
