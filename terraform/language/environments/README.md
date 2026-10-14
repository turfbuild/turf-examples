# One configuration, one stack per environment

Staging and production are the same files. The workspace name picks the state
slot; `env/<name>.tfvars` carries what differs; and a change is promoted by
bumping one variable and planning each environment in turn, with a gate on
production that asks before it moves.

```
env/staging.tfvars      environment = "staging"     replicas = 1
env/production.tfvars   environment = "production"  replicas = 3
```

Credential-free: `hashicorp/random` and the `hashicorp/tfcoremock` mock
provider stand in for a service.

## In plain terms

Copying a configuration per environment is how drift between environments
starts. Here there is one configuration and two workspaces — OpenTofu
workspaces, the state slots a `backend` block addresses by name. Opening the
configuration as `staging` or `production` selects the slot; the plan reads the
environment's own values from its tfvars file; nothing in `main.tf` knows which
it is.

## What this demonstrates

- **`workspace_name` selects the slot; `var_file` carries the environment.**
  Through the MCP tools: `init`, then
  `open({ workspace_name: "staging", workspace_alias: "staging" })`
  and `up({ workspace_alias: "staging", var_file: ["env/staging.tfvars"] })`;
  the same for `production` under its own alias. `open` reports
  `state_path` under `terraform.tfstate.d/<name>/`. `list` shows both.
- **Promotion is a plan per environment.** Bump `app_version`, plan staging,
  apply; plan production, apply. The diff is one string.
- **The steps are Turf actions, in one file for both environments.**
  `promote.turf.hcl` — tofu and terraform ignore it by its name; Turf lays it
  over `main.tf` at every plan — declares two `turf_action`s, the built-in
  action the agent driving Turf carries out itself (the apply stops at
  `awaiting_actions`, the agent does the step, and answers with
  `apply(action_results)`):
  - `smoke`, `after_create`/`after_update`: read the service back and confirm
    the version and replica count; a failure taints it.
  - `gate`, `before_update`, with `condition = var.environment == "production"`:
    ask whether the version has soaked in staging; a "no" is a failure carrying
    the user's reason, and production stays where it is. The condition is what
    keeps the question out of staging's own rollout.

## Prerequisites

- **Turf** (the Turf CLI or any MCP client pointed at `turf-mcp-server`; see
  [Running the examples](../../../README.md#running-the-examples)). No cloud
  account, no credentials.

## Usage

```bash
turf -C terraform/language/environments up -var-file=env/staging.tfvars
```

The CLI drives the default workspace; the per-environment slots are the MCP
flow above (or `TF_WORKSPACE` where the client honours it). Approve the plan,
then run production the same way with `env/production.tfvars`.

## Cleanup

`destroy` each workspace, then `close` it. Nothing real was created.
