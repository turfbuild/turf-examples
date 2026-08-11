# chat — compose Scalr features in one local session

Scalr's OPA policy and variable injection fire only on **Scalr-executed** runs; a
state-storage-only workspace (Turf's local model) gets none of them. Turf composes them
anyway — a local session reads the Scalr API through the **Scalr MCP server** and
evaluates policy through an **OPA MCP server**, all inside the agent loop.

A walkthrough of a real run, with screenshots: **[turf.build/demo/scalr](https://turf.build/demo/scalr/)**

This directory ships **no plot at all** — only this README and `.turf/` (turf.yaml, the
`scalr` skill, the banner). On your first prompt the agent `config_init`s a *fresh* plot
here, `declare_backend`s a `remote` backend bound to the `turf-scalr-chat` workspace
`../setup` created — a *state-storage-only* remote workspace, so Turf still plans/applies
locally while Scalr holds the state — then authors the `aws` provider and the VPC module
live, from your prompt. The generated `*.tfplot.hcl` units (and any local state) are
git-ignored, so a run leaves your checkout clean — nothing to reset.

## How it works

`.turf/turf.yaml` wires two external MCP servers via the `mcps:` overlay, so the agent
sees three tool namespaces at once:

| Prefix | Server | Role |
|--------|--------|------|
| `turf_*`  | built-in turf-mcp-server | plan/apply engine (incl. `turf_plan_export`) |
| `scalr_*` | `scalr/mcp-server` (docker) | read the Scalr API — variables, modules, policy |
| `opa_*`   | `orygn/opa-mcp` (docker/npx) | evaluate the plan against rego |

The `scalr` skill in `.turf/skills/scalr/` teaches the agent the call sequences
(`references/mcp.md`).

The same file also carries a `branding:` section, giving this directory a Scalr look and
voice: the `SCALR` banner (`.turf/scalr-banner.txt`), the `surf` theme, a Scalr welcome,
and standing instructions to treat policy as a pre-approval gate. Because nothing is checked
in as a plot, those `branding.additional_instructions` are also where the session is told to
`config_init` a fresh plot, `declare_backend` a `remote` backend for the `turf-scalr-chat`
workspace (state-storage-only), and open it — never a local backend. Branding is look and
voice only — turf is not renamed (the binary, status bar, and agent badge still say `turf`),
the tool namespace stays `turf_*`, and no approval gate is relaxed. Your own `/theme` pick
still overrides the branded default.

## Prerequisites

- **`../setup` applied** — creates the `region` variable, the published module, and the
  OPA policy group. For the policy gate, apply it with `-var enable_policy_group=true`
  (and `-var policy_branch=<branch>` if the policies aren't on the repo's default
  branch).
- **Docker** (both MCP servers are stdio containers; the OPA one also runs via `npx`).
- **A Scalr token for the MCP server:**
  ```bash
  export SCALR_API_TOKEN="$SCALR_TOKEN"
  export SCALR_API_URL="https://<your-account>.scalr.io"
  ```
- **A Scalr CLI token for the state backend** — the remote backend authenticates
  separately from the MCP server. Run `turf login <your-account>.scalr.io` (writes
  `~/.terraform.d/credentials.tfrc.json`) or export `TF_TOKEN_<host>` (dots → `_`, dashes →
  `__`). State is written to the `turf-scalr-chat` workspace in Scalr.
- **Local AWS credentials** — Turf plans locally, so the AWS provider authenticates from
  your environment, not Scalr. No AWS resources are created — the demo is plan-only for
  cloud infra; only workspace *state* is stored in Scalr.

## Run it

`--allow-path ..` lets the file tools read the shared policy repo
(`integrations/scalr/policies/`) so the agent can fetch the rego the policy group points
at; OPA evaluates it inline, so it never needs host-file access itself.

Grant the parent rather than just `../policies`: the agent gets its bearings by listing the
directory the policies live beside, and the narrower grant makes that fail with
*"outside the allowed directories"* before it ever reaches the rego. Note a
`chat/policies` symlink is not a way around this — the file tools resolve symlinks on both
sides of the check precisely so a link can't reach outside the allowed roots.

```bash
turf -C integrations/scalr/chat --allow-path .. chat
```

### Prompt 1 — pull a variable, add a module, gate the plan

Paste this prompt:

> Pull the `region` variable from the demo Scalr workspace, configure the `aws`
> provider for it, and add `<module_source>` (`~> 5.0`) as `vpc` — a minimal VPC
> named `turf-demo` with a `Name` tag only. Plan it. Before approving, ask Scalr which
> policy group governs this workspace's environment, read each policy's rego from the
> repo it points at, evaluate the exported plan with OPA, and gate approval on each
> policy's enforced level. Don't apply.

The module doesn't inject an `Environment` tag, and `require_environment_tag` is
**hard-mandatory**, so the gate **blocks** (4 denials) and the agent refuses to approve.

### Prompt 2 — remedy with the module's tag

> Add `Environment = "dev"` to the vpc module's `tags`, replan, re-export, and re-check
> the policy. If `deny` is empty, show me the clean gate. Still don't apply.

One `tags` input, propagated by the module's `merge(var.tags, …)`, fixes all four
resources; OPA returns an empty `deny` and the gate clears — governance caught at the
local plan and remediated pre-apply, in the same session.

---

Scalr is a trademark of Scalr, Inc.; Turf is not affiliated with, endorsed by, or
sponsored by Scalr, Inc. See [Trademarks](../README.md#trademarks).
