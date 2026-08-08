plot {
  version = 1
  name    = "scalr-plot"
  intent  = "The conversational twin of ../state-backend: the same random workload, authored ad-hoc as plot units by the declare_* tools, but backed by the Scalr remote backend so state + outputs land in the turf-scalr-plot workspace."

  # Same Scalr workspace pattern as the coded example, expressed as the plot's
  # backend. Literals (backends can't read variables): edit `hostname`, and keep
  # `organization` / `workspaces.name` in sync with ../setup (turf-demo /
  # turf-scalr-plot). Auth is out-of-band (terraform login <acct>.scalr.io).
  backend "remote" {
    hostname     = "turf.scalr.io"
    organization = "turf-demo"

    workspaces {
      name = "turf-scalr-plot"
    }
  }
}
