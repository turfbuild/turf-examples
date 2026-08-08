terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # State lives in a Scalr workspace instead of a local file. The workspace runs in
  # "state storage only" mode (execution_mode = "local", created by ../setup), so
  # Turf plans/applies locally and Scalr just stores the state + variables.
  #
  # Backend blocks can't use HCL variables, so these are literals:
  #   - hostname     — edit to your Scalr account (e.g. myacct.scalr.io)
  #   - organization — the Scalr *environment* name (../setup creates "turf-demo")
  #   - workspaces.name — must already exist (../setup creates "turf-scalr-coded")
  #
  # Auth is out-of-band: run `terraform login <acct>.scalr.io` (writes
  # credentials.tfrc.json) or export TF_TOKEN_<acct>_scalr_io=<token> — dots in the
  # hostname become underscores, dashes become double underscores.
  backend "remote" {
    hostname     = "turf.scalr.io"
    organization = "turf-demo"

    workspaces {
      name = "turf-scalr-coded"
    }
  }
}
