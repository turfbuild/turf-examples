# Scalr remote backend — reference

## State-storage-only vs remote-run

A Scalr workspace has an **execution mode**:

- **`remote`** (default) — Scalr runs the plan/apply on its own workers. Classic
  Terraform/OpenTofu executes server-side. **Not** what we want with Turf: it
  bypasses Turf's local planning/agentic loop.
- **`local`** ("State storage only" in the UI) — the CLI runs the plan/apply; Scalr
  only stores state, variables, and (optionally) evaluates policies. **This is the
  mode to use with Turf.** No run is executed on Scalr, so there's no run charge.

Set it on the `scalr_workspace` resource:

```hcl
resource "scalr_workspace" "example" {
  name           = "turf-scalr-chat"
  environment_id = scalr_environment.demo.id
  execution_mode = "local"
  iac_platform   = "opentofu"
}
```

## Token environment variables

The `remote` backend authenticates via a CLI credential, not the `scalr` provider:

- `turf login <acct>.scalr.io` — interactive; writes
  `~/.terraform.d/credentials.tfrc.json`.
- `TF_TOKEN_<host>` — the host with dots replaced by underscores and dashes by
  double underscores. For `my-acct.scalr.io` that is
  `TF_TOKEN_my__acct_scalr_io`.

The `scalr` **provider** (used in the setup/bootstrap config, not the backend) reads
`SCALR_TOKEN` and `SCALR_HOSTNAME` instead.

## Chicken-and-egg

The config that *creates* the Scalr workspaces (`../setup`) can't itself use a Scalr
workspace for state — it keeps `backend "local"`. Any *other* config that wants Scalr
to hold its state points `backend "remote"` at a workspace setup created.
