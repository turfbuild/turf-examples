plot {
  version = 1
  name    = "local-module"
  intent  = "A plot that calls a local module by a relative source path — the portable-local-module showcase. The source is stored verbatim, so the whole directory can be committed to git and cloned anywhere."

  backend "local" {
    path = "terraform.tfstate"
  }
}
