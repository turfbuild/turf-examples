# A configuration that calls a local module by a relative source path — the
# portable-local-module showcase. The source is a plain relative path, so the
# whole directory can be committed to git and cloned anywhere.
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Calls the local ./modules/greeting module. The source is a path relative to
# THIS configuration directory (Terraform's rule) — no absolute path is baked
# in, so the configuration stays portable across machines and git clones.
module "greeting" {
  source = "./modules/greeting"

  prefix = "hello"
}
