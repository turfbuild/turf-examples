plot {
  version = 1

  # The only unit checked in. The agent authors the aws provider and the vpc module
  # live during the session (see README) — this file just names the plot and pins a
  # local backend so the demo is plan-only and credential-light.
  intent = "Compose Scalr's registry variable and OPA policy in one local turf session: pull a workspace variable, feed a private-registry module, and gate the plan on the Scalr policy group."
  name   = "scalr-chat"

  backend "local" {
    path = "terraform.tfstate"
  }
}
