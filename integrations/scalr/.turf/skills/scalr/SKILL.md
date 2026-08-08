---
name: scalr
description: Conventions for authoring Turf configurations backed by Scalr — the remote backend, state-storage-only workspaces, the private module registry source format, and OPA policy expectations. Load when working in a Scalr-backed directory.
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
- Auth is **out-of-band**: `terraform login <acct>.scalr.io` (writes
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

**OPA policy.** Policies are sourced from a VCS repo (a `scalr_policy_group`). Each
`*.rego` uses `package terraform`, reads the plan at `input.tfplan`, and returns a
`deny` array of strings; `scalr-policy.hcl` sets each policy's `enforcement_level`
(`advisory` | `soft-mandatory` | `hard-mandatory`).

## How to apply

- When adding state to a Scalr-backed dir, write the `backend "remote"` block with
  literal `hostname`/`organization`/`workspaces.name`; never try to parameterize a
  backend with variables.
- Keep the environment/workspace names in the backend blocks in sync with what
  `../setup` creates.
- Load `references/backend.md` for the state-only rationale and the token-env-var
  encoding rules.
