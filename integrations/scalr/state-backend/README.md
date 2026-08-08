# Scalr remote backend — coded interop test

Store Turf/OpenTofu state in a **Scalr workspace** instead of a local file. A trivial,
credential-free `random` workload rides along so there's real state to persist — and
a real output to read back through the [Scalr MCP server](../README.md#read-it-back-with-the-scalr-mcp-server).

This is the **codified** end of the spectrum: plain hand-authored `.tf` files (a tofu
configuration). Its conversational twin is [`../plot`](../plot).

## What This Demonstrates

`providers.tf` swaps the usual `backend "local"` for `backend "remote"` pointed at Scalr:

```hcl
backend "remote" {
  hostname     = "example.scalr.io"   # your Scalr account
  organization = "turf-demo"          # the Scalr environment (created by ../setup)
  workspaces {
    name = "turf-scalr-coded"         # the workspace (created by ../setup)
  }
}
```

- **State** is written to the `turf-scalr-coded` workspace in the `turf-demo`
  environment. The workspace is **state-storage-only** (`execution_mode = "local"`),
  so Turf runs the plan/apply locally and Scalr only stores the result — no remote
  run, and Turf keeps its agentic loop.
- **Auth is out-of-band.** Backend blocks can't reference HCL variables, so the
  backend authenticates from `terraform login <acct>.scalr.io` (writes
  `credentials.tfrc.json`) or from `TF_TOKEN_<acct>_scalr_io` in the environment
  (dots in the hostname become underscores, dashes become double underscores).

## Prerequisites

- A Scalr account, and the environment + workspace created by
  [`../setup`](../setup) (`turf -C integrations/scalr/setup up`).
- `hostname` in `providers.tf` edited to your account.
- A Scalr token available to the backend (`terraform login <acct>.scalr.io`).
- The Turf CLI, or any MCP client pointed at `turf-mcp-server`.

## Usage

```bash
terraform login example.scalr.io          # once — writes credentials.tfrc.json
turf -C integrations/scalr/state-backend up
```

> **Interop note:** `turf` and plain `tofu` share the same Scalr workspace state, so
> you can drive this with either. For the `tofu` baseline, set the backend credential
> and run init/apply:
>
> ```bash
> export TF_TOKEN_turf_scalr_io="$SCALR_TOKEN"
> tofu -chdir=integrations/scalr/state-backend init && \
> tofu -chdir=integrations/scalr/state-backend apply
> ```
>
> See the [integration README](../README.md#interop-notes).

## Verify

```bash
turf -C integrations/scalr/state-backend output
# full_name = "<pet>-<suffix>"
```

The same state now lives in Scalr: open the `turf-scalr-coded` workspace in the UI
(it shows a new state version), or read `full_name` back with the Scalr MCP server —
see [the integration README](../README.md#read-it-back-with-the-scalr-mcp-server).

## Cleanup

```bash
turf -C integrations/scalr/state-backend destroy
```

`destroy` empties the workload; the (now-empty) state version remains in the Scalr
workspace. To remove the workspace itself, tear down [`../setup`](../setup).
