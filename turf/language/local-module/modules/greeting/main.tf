terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "prefix" {
  type        = string
  description = "Word prepended to the generated pet name."
}

resource "random_pet" "name" {
  prefix = var.prefix
  length = 2
}

output "greeting" {
  description = "The prefixed pet name, e.g. hello-superb-mongoose."
  value       = random_pet.name.id
}
