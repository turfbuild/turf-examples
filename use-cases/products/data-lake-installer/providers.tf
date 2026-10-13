terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Plan-only without credentials. Every flag below turns off a call the provider
# would otherwise make at configure time; with them, a create-only plan of the
# resources here touches no AWS API and needs no account. A customer running
# the installer for real drops the four skip_* lines and the mock keys, and the
# provider authenticates from their environment or profile as usual.
provider "aws" {
  region     = var.region
  access_key = var.plan_only ? "mock_access_key" : null
  secret_key = var.plan_only ? "mock_secret_key" : null

  skip_credentials_validation = var.plan_only
  skip_requesting_account_id  = var.plan_only
  skip_metadata_api_check     = var.plan_only
  skip_region_validation      = var.plan_only
}
