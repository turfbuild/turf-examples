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

# tfcoremock stands in for the resource the actions gate — it keeps the example
# credential-free. The turf_* actions themselves need no provider at all.
provider "tfcoremock" {
  use_only_state = true
}
