---
name: tagging-policy
description: Enforce the organization's resource tagging and naming standard. Use whenever the user creates, updates, or adopts a billable cloud resource.
---

# Tagging & naming policy

A guardrail skill: it does not create resources on its own — it shapes the
configuration of whatever flow is already running (`skill_adhoc` for free-form
requests, `skill_codified` for HCL) so every managed resource meets the org
standard before the plan is approved and applied.

## When to use

- Any `declare_resource` / `effect_apply` for a billable cloud resource.
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
2. Inject the tag block into each resource's configuration.
3. `declare_resource` and review the diff. A first-time tag addition shows as `~`
   (in-place update); a brand-new resource shows as `+`.
4. `plan_approve` + `effect_apply` once the diff is clean and the user has approved it.

If a provider exposes tags under a different key (e.g. AWS/azurerm/google use a
`tags` map, azapi nests them in `body`, Kubernetes uses `metadata.labels`), map
the container per `references/tags.md`. The tag *values* stay identical across
providers — only the container key differs.
