# Terraform Actions

Demonstrates **Terraform Actions** (introduced in Terraform 1.14): `action` blocks
invoked around a resource's lifecycle via `lifecycle.action_trigger`. Turf runs each
triggered action as a gating **invoke** effect, ordered relative to the resource
operation. Credential-free — the `hashicorp/tfcoremock` mock provider is the first to
ship actions and resolves straight from the public registry.

## What This Demonstrates

`tfcoremock_simple_resource.web` attaches two triggers (see `main.tf`):

- a **`before_create` gate** — an action that must succeed *before* the resource is
  created (model a policy/pre-flight check);
- an **`after_create` hook** with `on_failure = continue` — an action that fires *after*
  the resource exists, and whose failure won't fail the run (model a non-critical
  announcement).

Turf orders these as effects: `invoke(gate)` → `create(web)` → `invoke(announce)`.

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
- **`on_failure`** — `halt` (default: a failed action stops the run) or `continue`
  (record the failure and proceed). Gates typically `halt`; post-hooks often `continue`.
- An action writes **no state** — it's imperative, not a managed resource.

## Prerequisites

- **Turf** (the Turf CLI or any MCP client pointed at `turf-mcp-server`) — Turf parses the
  `action` blocks and runs the invoke effects.
- No cloud account, no credentials.

## Usage

```bash
turf -C terraform/language/actions
```

The planned invocations show up in the phase's plan (`action_invocations`), and each
fires as an `invoke` effect in order.

> Turf also ships its own **native** actions — `turf_confirm` (a human gate) and
> `turf_action` (an agent step) — that need no provider. See
> [`../turf-actions`](../turf-actions).

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
