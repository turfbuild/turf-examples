---
name: scalr
description: Working with Scalr from a local Turf session — the remote backend + state-storage-only workspaces, and composing Scalr's otherwise remote-only features locally via MCP: pull a workspace variable and feed a registry module, and gate plan approval on an OPA policy. Load when a config targets a *.scalr.io host or the turf.yaml wires the scalr/opa MCP servers.
---

## When to use

Load this skill when a configuration in this repo targets **Scalr** — i.e. its
backend is `remote` pointed at a `*.scalr.io` host, or you are authoring a plot/tofu
config that should store state and variables in a Scalr workspace.

## The standard

**Remote backend → Scalr.** State lives in a Scalr *workspace* inside a Scalr
*environment*, not a local file:

```hcl
backend "remote" {
  hostname     = "<acct>.scalr.io"   # the account host (literal — backends can't read vars)
  organization = "<environment>"     # a Scalr environment name
  workspaces { name = "<workspace>" }
}
```

- Use **state-storage-only** workspaces (`execution_mode = "local"` on the
  `scalr_workspace`) so Turf plans/applies locally and Scalr just stores the
  result. Do not use remote-run workspaces — they run classic Terraform on Scalr's
  side and bypass Turf's agentic loop.
- The workspace and environment must **already exist**. Provision them as code with
  the `scalr` provider (see `../setup`), not by hand.
- Auth is **out-of-band**: `turf login <acct>.scalr.io` (writes
  `credentials.tfrc.json`) or `TF_TOKEN_<acct>_scalr_io`. The `scalr` *provider*
  (used only in the setup config) reads `SCALR_TOKEN` instead.

**Module registry.** Consume Scalr private-registry modules by their four-part
source, and always pin a `version`:

```hcl
module "x" {
  source  = "<acct>.scalr.io/<namespace>/<name>/<provider>"
  version = "1.2.3"
}
```

**OPA policy.** Policies live in a repo (a `scalr_policy_group`) and also drive the
local gate below. Each `*.rego` uses `package terraform`, reads the plan at
`input.tfplan`, and returns a `deny` **set** of strings; `scalr-policy.hcl` sets each
policy's `enforcement_level` (`advisory` | `soft-mandatory` | `hard-mandatory`).
Write rego in **v1 syntax** (`import rego.v1`; `deny contains reason if { … }`) — the
OPA MCP server runs OPA 1.0.

## Composing Scalr features in a local session (MCP)

Scalr's OPA policy, variable injection, and provider configs fire only on
**Scalr-executed** runs — a state-storage-only workspace (Turf's model) gets none of
them. Turf composes them anyway by reading the Scalr API through MCP inside the agent
loop. When `turf.yaml` wires the `scalr` and `opa` MCP servers, their tools appear as
`scalr_*` and `opa_*` (Turf's own tools stay `turf_*`). Two playbooks —
**load `references/mcp.md` for the exact call sequences**:

- **Pull a variable → feed a module.** Read a non-sensitive workspace variable with
  `scalr_list_variables` / `scalr_get_variable`, then `turf_declare_module` a
  private-registry module using that value. (Sensitive values are write-once and never
  returned — only non-sensitive vars are pullable.) Which workspace? The one this config
  binds to — resolve it from the config's `backend "remote"` / the workspace the session
  opened, or the name the user gives you. (This repo's `chat` demo targets the workspace
  `../setup` created; its README names it.)
- **Policy gate at approval.** Discover the Scalr policy group for the workspace's
  environment (`scalr_list_policy_groups` → `scalr_get_policy_group`) to learn each
  policy's `enforced-level` and its `vcs_repo`; fetch the matching `<name>.rego` from
  that repo (Scalr returns metadata, never rego bytes); `turf_plan_export` → evaluate
  with `opa_rego_eval` (inline `source`, `input = { "tfplan": <plan> }`) → refuse
  `turf_plan_approve` per level (`hard-mandatory` blocks; `soft-mandatory` blocks unless
  overridden; `advisory` warns). No group linked → eval the local rego as advisory.

## How to apply

- When adding state to a Scalr-backed dir, write the `backend "remote"` block with
  literal `hostname`/`organization`/`workspaces.name`; never try to parameterize a
  backend with variables. (A config may instead declare **no** backend and open a
  state-storage-only remote workspace at runtime — carrying the same
  `hostname`/`environment`/`workspace` identity from its instructions — when it wants to
  stay generic; the `chat` demo does this.)
- Whether it lives in a backend block or is passed to `workspace_open`, keep the
  environment/workspace names in sync with whatever provisioned that workspace.
- Load `references/backend.md` for the state-only rationale and the token-env-var
  encoding rules; load `references/mcp.md` for the variable→module and policy-gate
  call sequences. (Read these with `read_skill_file` — this is a project skill, not a
  `turf_*` built-in, so `turf_read_skill_file` won't find it.)
