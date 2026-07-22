terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource groups to deploy, keyed by an arbitrary instance key (here, a region
# short-name). Keying by a stable string means adding or removing a region only
# touches that one instance — module.resource_group["eastus"] stays put when
# "westus" is added or dropped.
variable "resource_groups" {
  description = "Resource groups to deploy, keyed by instance key."
  type = map(object({
    location = string
    tags     = optional(map(string), {})
  }))
  default = {
    eastus = { location = "East US" }
    westus = { location = "West US 2" }
  }
}

# One AVM resource-group module instance per entry in var.resource_groups. This
# is the *codified* (HCL) form of multi-instance composition: turf's full walk
# (plan_new / replan) expands the for_each and emits
# module.resource_group["<key>"].* addresses. The ad-hoc analogue — driving the
# same outcome through the declare_module tool's for_each/count meta-args, no
# hand-written HCL — is in README.md.
module "resource_group" {
  source   = "Azure/avm-res-resources-resourcegroup/azurerm"
  version  = "~> 0.2"
  for_each = var.resource_groups

  name     = "rg-avm-demo-${each.key}"
  location = each.value.location
  tags     = each.value.tags
}

# --- count alternative -------------------------------------------------------
# When the instances are homogeneous and you just want N of them, count works
# too (addresses module.resource_group_n[0], [1], …). Left commented so the
# example applies a single, unambiguous set; uncomment to compare the shapes.
#
#   variable "rg_count" {
#     type    = number
#     default = 2
#   }
#
#   module "resource_group_n" {
#     source   = "Azure/avm-res-resources-resourcegroup/azurerm"
#     version  = "~> 0.2"
#     count    = var.rg_count
#     name     = "rg-avm-demo-${count.index}"
#     location = "East US"
#   }
