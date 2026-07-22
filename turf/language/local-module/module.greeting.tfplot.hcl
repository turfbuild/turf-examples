turf {
  intent = "Calls the local ./modules/greeting module. The source is a path relative to THIS configuration directory (Terraform's rule), stored verbatim — no absolute path is baked in, so the plot stays portable across machines and git clones."

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

module "greeting" {
  source = "./modules/greeting"

  prefix = "hello"
}
