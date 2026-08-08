# Turf, tailored for Scalr

[Scalr](https://scalr.io) is a remote state/backend and Terraform control plane. This
integration runs **Turf as the engine and Scalr as the control plane**: Turf plans and
applies locally, Scalr stores the state + variables and enforces policy, and the
**Scalr MCP server** reads it all back into your coding assistant. Everything Scalr-side
is provisioned as code with the Scalr Terraform provider.

The workload is deliberately trivial and **credential-free** (`hashicorp/random`) so the
interop test needs nothing but a Scalr token.

## What's here

| Path | Dialect | What it shows |
|------|---------|---------------|
| [`setup/`](setup)                 | tofu (local state) | Provisions the Scalr side with the `scalr` provider: an environment, two **state-storage-only** workspaces, a variable, and (optionally) a VCS provider + OPA **policy group**. |
| [`state-backend/`](state-backend) | tofu | The **coded interop test** — `backend "remote"` → Scalr, a `random` workload, a `full_name` output. |
| [`plot/`](plot)                   | plot | The **conversational** twin — the same workload authored as `*.tfplot.hcl` plot units, Scalr-backed. |
| [`policies/`](policies)           | OPA  | `scalr-policy.hcl` + a `readable_pet_names.rego`, sourced by the policy group over VCS. |
| [`.turf/`](.turf)                 | —    | Model config (`turf.yaml`) + a `scalr` **skill** the Turf agent discovers here. |

## Feature map (the "tailored" bits)

- **Scalr remote backend** — `state-backend/` and `plot/` both point `backend "remote"`
  at a Scalr workspace. State-storage-only (`execution_mode = "local"`) keeps Turf
  executing locally; Scalr just stores state + variables.
- **Setup as code** — `setup/` creates the environment, workspaces, variables, VCS
  provider, and policy group with the `scalr` provider. No click-ops.
- **OPA policy** — `policies/` holds the guardrail; `setup/` attaches it as a
  `scalr_policy_group` sourced from this repo (only when you supply a `vcs_token`).
- **Module registry** — see [Consuming a registry module](#consuming-a-scalr-registry-module).
- **MCP read-back** — see [Read it back with the Scalr MCP server](#read-it-back-with-the-scalr-mcp-server).

## Prerequisites

- A Scalr account (`<acct>.scalr.io`).
- The Turf CLI, or any MCP client pointed at `turf-mcp-server`.
- A Scalr token. Two mechanisms, used in different places:
  - the **`scalr` provider** (in `setup/`) reads `SCALR_TOKEN` — `export SCALR_TOKEN=…`;
    for local runs it also wants the account id (`SCALR_ACCOUNT_ID`, or the
    `scalr_account_id` tfvar);
  - the **`remote` backend** (in `state-backend/` and `plot/`) uses a CLI credential —
    `terraform login <acct>.scalr.io` (or `TF_TOKEN_<acct>_scalr_io`).

## Run order

Edit `hostname` in `state-backend/providers.tf` and `plot/main.tfplot.hcl` to your
account first (backend blocks can't read variables). Then:

```bash
# 1. Provision the Scalr side (environment + state-only workspaces + policy group).
#    For LOCAL provider runs, Scalr needs the account id too — export it (or set the
#    scalr_account_id tfvar).
export SCALR_TOKEN="…"
export SCALR_ACCOUNT_ID="acc-…"
cd integrations/scalr/setup && cp terraform.tfvars.example terraform.tfvars   # fill in scalr_hostname
turf -C integrations/scalr/setup up

# 2. Coded interop test — state lands in the turf-scalr-coded workspace.
terraform login example.scalr.io
turf -C integrations/scalr/state-backend up
turf -C integrations/scalr/state-backend output      # full_name = "<pet>-<suffix>"

# 3. Conversational plot — same, in the turf-scalr-plot workspace.
turf -C integrations/scalr/plot up
```

Tear down in reverse: `destroy` the two example dirs, then `turf -C integrations/scalr/setup destroy`.

## Interop notes

A live end-to-end test against a Scalr account confirmed the round trip in both
directions:

- **`tofu` and `turf` share the same state.** `state-backend/` was applied with plain
  `tofu`; turf then opened the same `turf-scalr-coded` workspace, read the state
  `tofu` had written, planned the identical configuration to an all-NoOp, and read the
  `full_name` output back. Nothing is written locally — there is no `terraform.tfstate`
  in the example directory.
- **turf uses the backend for state and locking only.** `execution_mode = "local"` on
  the workspace is not a limitation to work around, it is the arrangement: turf plans
  and applies locally with its own engine and never triggers a run on Scalr's runner.
  The workspace is where state, locks, and version history live.
- **Credentials are the ordinary Terraform ones.** `tofu login <acct>.scalr.io` (which
  writes `~/.terraform.d/credentials.tfrc.json`) or `TF_TOKEN_<host>` — turf reads the
  same CLI configuration `tofu` does. Host encoding: dots → `_`, dashes → `__`, so
  `turf.scalr.io` is `TF_TOKEN_turf_scalr_io`.

One thing to know when driving these by hand: with `workspaces { name = … }` the
backend addresses exactly one remote workspace, so `workspace_open` takes **no**
workspace name — a name is only meaningful with `workspaces { prefix = … }`, where it
is the suffix. This is Terraform's rule, not a turf one.

The `tofu` baseline stays a useful comparison at any point:

```bash
cd integrations/scalr/state-backend
export TF_TOKEN_turf_scalr_io="$SCALR_TOKEN"
tofu init && tofu plan     # should agree with turf's plan
```

## Read it back with the Scalr MCP server

Once Turf has written state, add Scalr's MCP server to your assistant and read the
workspace back — outputs, variables, and policy results — without leaving the editor:

```bash
# Claude Code (remote MCP over OAuth; an account admin must enable the AI Assistant
# integration under Account Settings → Integrations first):
claude mcp add --transport http scalr https://example.scalr.io/mcp
# then, in Claude Code:  /mcp  →  scalr  →  Authenticate
```

Then ask, e.g. *"show the outputs and variables of the `turf-scalr-coded` workspace,
and any policy checks."* The MCP server answers from the live account via tools like
`get_workspace`, `list_variables`, and `list_policy_groups` — the `full_name` Turf just
wrote, the `greeting` variable `setup/` created, and the `readable_pet_names` policy
result. This is the read layer that complements Turf's write layer.

> Prefer a local server? Run `scalr/mcp-server:latest` in Docker with
> `SCALR_API_TOKEN` + `SCALR_API_URL`. See the [Scalr MCP docs](https://docs.scalr.io).

## Consuming a Scalr registry module

Scalr's private module registry uses a four-part source, and **`version` is required**:

```hcl
module "example" {
  source  = "example.scalr.io/<namespace>/<name>/<provider>"
  version = "1.0.0"
  # …inputs…
}
```

Publishing a module needs a VCS-linked module with tagged releases (a
`scalr_module`), which is out of scope for this credential-free example — the source
format above is what a Scalr-backed config would use. The `scalr` skill in `.turf/`
teaches the Turf agent this convention.

## References

- Scalr CLI / remote backend — https://docs.scalr.io/docs/cli
- Private module registry — https://docs.scalr.io/docs/private-module-registry
- OPA policy as code — https://docs.scalr.io/docs/policy-as-code
- Scalr Terraform provider — https://registry.terraform.io/providers/Scalr/scalr/latest/docs
