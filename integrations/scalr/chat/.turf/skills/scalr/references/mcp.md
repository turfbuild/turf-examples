# Composing Scalr features locally via MCP — call sequences

The turf agent connects to two external MCP servers (wired in `.turf/turf.yaml` under
`mcps:`): **`scalr`** (`scalr/mcp-server`, reads the Scalr API) and **`opa`**
(`orygn/opa-mcp`, evaluates rego). Their tools are prefixed `scalr_*` and `opa_*`;
Turf's own engine is `turf_*`. Export `SCALR_API_TOKEN` and `SCALR_API_URL` before
launching turf so the Scalr server authenticates.

These sequences are verified against the live account — use them verbatim. Note the
Scalr list tools filter by **ID**, not name: resolve a name to its ID first.

## Playbook 1 — pull a variable, feed a module

Goal: parameterize a module with a value that lives in a Scalr workspace, without
Scalr running the plan.

1. **Resolve the workspace ID.** `scalr_list_workspaces` with
   `{ "filter_name": "<workspace-name>" }` → `resources[0].id` (a `ws-…` id) and its
   `environment` (an `env-…` id — keep it for Playbook 2). Take `<workspace-name>` from the
   config's `backend "remote"` block / the workspace the session opened, or from the user —
   don't assume a name. (In the `chat` demo it's the workspace `../setup` created, holding
   this demo's `region` variable; its README names it.)
2. **Find the value.** `scalr_list_variables` with
   `{ "filter_workspace": "<ws-id>", "filter_key": "region" }` returns
   `{ "resources": [ { key, value, sensitive, category, id, … } ] }`. Each
   non-sensitive entry carries its `value` inline (e.g. `region` → `us-east-1`).
   **Only non-sensitive `category=terraform` vars return a value** — sensitive vars are
   write-once and come back masked, so never rely on pulling a secret this way.
3. **News-up the module.** `turf_declare_module` with the module's four-part registry
   `source` (`<host>/<namespace>/<name>/<provider>`, from `setup`'s `module_source`
   output) + a pinned `version`, passing the pulled value as an input. Configure the
   module's provider (e.g. `aws`) with the same region — provider creds come from the
   **local** environment, since Scalr isn't executing this run.
4. `turf_plan_new` and review — the planned module inputs carry the Scalr-sourced value.

## Playbook 2 — discover the Scalr policy group, enforce it locally

Goal: enforce the workspace's *Scalr-defined* governance against Turf's **local** plan,
at the moment of approval. Scalr's OPA policies fire only on Scalr-executed runs; here
the local session asks Scalr **what** to enforce and **at what level**, then evaluates
the same rego locally with the OPA server and gates approval accordingly.

**Scalr hosts the policy _definition_, not the rego bytes.** `scalr_get_policy_group`
returns each policy's `name` + `enforced-level` + `enabled`, the group's `vcs_repo`
(`identifier`/`branch`/`path`) and `opa_version` — but **never the rego source**. You
fetch the `.rego` from that repo. In this example the repo *is* this checkout, so a
local read of `<path>/<name>.rego` is the same source Scalr syncs.

1. **Discover the policy group** linked to the workspace's environment (the `env-…` id
   from Playbook 1 step 1, or `setup`'s `environment_id` output):
   ```json
   scalr_list_policy_groups { "filter_environment": "<env-id>" }
   ```
   For each returned group, get its policies + source (note `include` is a **list**):
   ```json
   scalr_get_policy_group { "policy_group": "<pgrp-id>", "include": ["policies"] }
   ```
   Read from the response: `vcs_repo { identifier, branch, path }`, `opa_version`, and
   each `included[].attributes` = `{ name, enabled, "enforced-level" }`
   (`advisory` | `soft-mandatory` | `hard-mandatory`). Skip policies with
   `enabled: false`.
   **Fallback:** if no group is linked (`count: 0`), evaluate the local
   `policies/*.rego` treating every policy as **advisory**, and say so.
2. **Fetch each policy's rego** from the group's `vcs_repo.path`, matching by name:
   read `<path>/<name>.rego` with the filesystem tool (e.g.
   `../policies/require_environment_tag.rego`). The policies dir sits outside the plot —
   one level up from `chat/` — so launch turf with `--allow-path ..` (resolved against the
   `-C` config dir) or the read fails as *"outside the allowed directories."* Grant the
   parent, not just `../policies`: getting your bearings by listing the directory the
   policies sit in otherwise fails the same way. A `chat/policies` symlink does not help —
   the file tools resolve symlinks on both sides of the check. (No local checkout? Fetch
   the file from the repo over the network — creds permitting.)
3. **Export the plan.** `turf_plan_export` → the standard `tofu show -json` document
   (`resource_changes[].change.after`, …).
4. **Evaluate** each policy against the plan. **Pass BOTH the rego and the plan
   inline** — the rego as `source`, the plan as `input` — never the file-path
   variants (`paths`/`inputPath`). The OPA server runs in a container and cannot read
   host files, so a path-based call fails with `PATH_NOT_ALLOWED` (don't bother
   writing the plan to a temp file first — it can't be read back):
   ```json
   opa_rego_eval {
     "query": "data.terraform.deny",
     "source": "<the rego bytes from step 2>",
     "input": { "tfplan": <the plan JSON from turf_plan_export> }
   }
   ```
   The `input` MUST wrap the plan under `tfplan` — a bare plan silently yields no
   violations (a false pass). Result shape:
   `{ "ok": true, "data": { "result": [ { "expressions": [ { "value": <deny array> } ] } ] } }`;
   the `deny` strings are that `value`.
5. **Gate on `enforced-level`** — refuse by simply **not calling `turf_plan_approve`**:

   | `enforced-level` | `deny` non-empty → |
   |---|---|
   | `hard-mandatory` | **Block.** Do not approve. Report the reasons. |
   | `soft-mandatory` | **Block, overridable.** Do not approve unless the user explicitly overrides via `user_prompt`. |
   | `advisory` | **Warn.** Surface the reasons; may proceed. |

   Approve (`turf_plan_approve`) only when every enabled policy passes, or an override is
   granted for a soft/advisory violation. An empty `deny` across all policies is a clean
   pass.

## Notes

- Rego must be **v1 syntax** (Scalr's `opa_version` is 1.x; the OPA MCP server runs
  OPA 1.0): `import rego.v1`, `deny contains reason if { some rc in
  input.tfplan.resource_changes; … }`. The `enforced-level` per policy is set in the
  repo's `scalr-policy.hcl`, but read it from `scalr_get_policy_group` at runtime — the
  API is the source of truth for what Scalr actually enforces.
- Scalr returns policy **metadata + enforcement + a VCS pointer, never rego content** —
  there is no get-policy-content tool; always fetch the `.rego` from `vcs_repo`.
- No Docker? The OPA server also runs as `npx -y @orygn/opa-mcp` (see `turf.yaml`). A
  non-container OPA *can* read host files given `OPA_MCP_ALLOWED_PATHS`, but inline
  `source` works for both — prefer it and skip the path wiring.
- The Scalr MCP server is read-mostly (plus create-variable/workspace); it never runs a
  plan/apply — Turf does, locally.
