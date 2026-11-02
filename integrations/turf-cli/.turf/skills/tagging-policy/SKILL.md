---
name: tagging-policy
description: Enforce the organization's resource tagging and naming standard. Use whenever the user creates, updates, or adopts a billable cloud resource.
---

# Tagging & naming policy

A guardrail skill: it does not create resources on its own — it shapes the
configuration of whatever flow is already running (`skill_deployment` runs it;
`skill_authoring` covers writing or editing the `.tf` files) so every managed
resource meets the org standard before the plan is approved and applied.

## When to use

- Any billable cloud resource you write into (or edit in) a `.tf` file, or that
  a plan you are about to approve would create or update.
- Importing or adopting existing resources — bring them up to standard on the
  first reconcile (a `~` update is expected and correct).

## The standard

Every resource MUST carry the required tags and follow the naming pattern. The
full key list, allowed values, and per-provider mapping are in
`references/tags.md` — load it with `read_skill_file` when you need specifics;
do not preload it.

- Required tags: `cost-center`, `owner`, `env`, `managed-by` (always `turf`).
- Naming: `<env>-<app>-<resource>`, lowercase — e.g. `prod-web-bucket`.

## How to apply

1. Confirm `env` and `owner` with the user if they are not already obvious from
   the request.
2. Write the tags into each resource's block in its `.tf` file — the `tags` map
   (or the provider's equivalent container, below). In a configuration the user
   wrote, edit their files only with their go-ahead.
3. `up`, then `plan`, and review the vended plan. A first-time tag addition
   shows as `~` (in-place update); a brand-new resource shows as `+`. If a
   convergence was already waiting at its plan gate or approval point, this `up`
   supersedes it.
4. `apply` with that plan's digest once the diff is clean and the user has
   approved it.

If a provider exposes tags under a different key (e.g. AWS/azurerm/google use a
`tags` map, azapi nests them in `body`, Kubernetes uses `metadata.labels`), map
the container per `references/tags.md`. The tag *values* stay identical across
providers — only the container key differs.
