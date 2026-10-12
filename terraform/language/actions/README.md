# Terraform Actions

Demonstrates **Terraform Actions** (introduced in Terraform 1.14): `action` blocks
invoked around a resource's lifecycle via `lifecycle.action_trigger`. Turf runs each
triggered action as an **action invocation** that gates what follows it, ordered
relative to the resource operation. Credential-free — the `hashicorp/tfcoremock` mock provider is the first to
ship actions and resolves straight from the public registry.

## What This Demonstrates

`tfcoremock_simple_resource.web` attaches two triggers (see `main.tf`):

- a **`before_create` gate** — an action that must succeed *before* the resource is
  created (model a policy/pre-flight check);
- an **`after_create` hook** with `on_failure = continue` — an action that fires *after*
  the resource exists, and whose failure won't fail the run (model a non-critical
  announcement).

Turf runs them in this order: `invoke(gate)` → `create(web)` → `invoke(announce)`.

## Action anatomy

```hcl
resource "tfcoremock_simple_resource" "web" {
  # ...
  lifecycle {
    action_trigger {
      events  = [before_create]                             # when to fire
      actions = [action.tfcoremock_simple_resource.gate]    # what to run
    }
  }
}

action "tfcoremock_simple_resource" "gate" {                # the action definition
  config { string = "preflight: change window open" }
}
```

- **`events`** — any of `before_create`, `after_create`, `before_update`,
  `after_update`, `before_destroy`, `after_destroy`.
- **`on_failure`** — `halt` (default: a failed action stops the run), `continue`
  (record the failure and proceed), or `taint` (`after_create` only: the resource is
  tainted, so the next plan replaces it). Gates typically `halt`; post-hooks often
  `continue`.
- An action writes **no state** — it's imperative, not a managed resource.

## Prerequisites

- **Turf** (the Turf CLI or any MCP client pointed at `turf-mcp-server`; see
  [Running the examples](../../../README.md#running-the-examples)) — Turf parses the
  `action` blocks and runs the action invocations.
- No cloud account, no credentials.

## Usage

```bash
turf -C terraform/language/actions up
```

The planned invocations are in the round's plan document (`action_invocations`), and
`up` summarizes them at the approval point (`plan.invocations`), per resource in the
order they run. Approving the plan with `apply` runs each one in that order.

## Turf's own action: `turf_action`

Turf also ships a **native** action that needs no provider, because the agent driving
Turf performs it. A `turf_action` carries a `prompt` (what to do, and what counts as
failure) and `inputs` (the values to do it with, evaluated like any action config,
`caller` included):

```hcl
action "turf_action" "smoke_test" {
  config {
    prompt = "GET inputs.url and expect 200; fail if it does not answer."
    inputs = { url = "https://${caller.string}/" }
  }
}
```

When an apply reaches one, it stops at `awaiting_actions` and returns each open request
with its `prompt` and evaluated `inputs`. The agent does the step with its own tools and
answers every request in one call, `apply(convergence_id, action_results)`, reporting
`succeeded`, the `progress` it made, and any `diagnostics`; the trigger's `on_failure`
decides what a failure does. A person's decision is a `turf_action` whose prompt tells
the agent to ask the user: there is no separate confirmation action.

## Real providers with actions

The mock provider keeps this example credential-free, but actions are a general
provider feature. Public providers already shipping them include:

| Provider           | Example action                         | Does                                  |
|--------------------|----------------------------------------|---------------------------------------|
| `hashicorp/local`  | `local_command`                        | runs a local command                  |
| `hashicorp/aws`    | `aws_lambda_invoke`                    | invokes a Lambda function             |
| `hashicorp/aws`    | `aws_ec2_stop_instance`                | stops an EC2 instance                 |
| `hashicorp/azurerm`| VM start/stop/restart                  | power-cycles a virtual machine        |

For example, with `hashicorp/local` you can run a script as an after-create hook:

```hcl
resource "terraform_data" "deploy" {
  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.local_command.notify]
    }
  }
}

action "local_command" "notify" {
  config {
    command   = "bash"
    arguments = ["-c", "echo deployed >> deploy.log"]
  }
}
```

## Cleanup

```bash
turf -C terraform/language/actions destroy
```

The mock provider persists nothing, so there's nothing to clean up beyond local state.
