# Turf-native actions (`turf_confirm`, `turf_action`)

Turf ships two built-in **actions** that put a human or the agent into the apply
loop. Unlike provider actions (see [the Terraform Actions example](../../../terraform/language/actions)), action types
prefixed `turf_` dispatch **in-process — no provider required** — and carry the
synthetic provider identity `turfbuild/turf`.

| Action         | Class        | Does                                                                 |
|----------------|--------------|---------------------------------------------------------------------|
| `turf_confirm` | elicitation  | asks a human for a continue/halt decision                           |
| `turf_action`  | sampling     | delegates a step to the agent, which performs it and reports back   |

## What This Demonstrates

`tfcoremock_simple_resource.production_bucket` binds both actions to its lifecycle
(see `main.tf`):

- a **`before_create` `turf_confirm` gate** — a person approves before the resource
  is created; a *halt* decision fails the invoke and leaves the create blocked;
- an **`after_create` `turf_action` hook** — the agent verifies a safety property
  (here: the store isn't publicly accessible) and reports success or failure, with
  `on_failure = halt` deciding the consequence.

Both appear in the plan's `action_invocations[]` (each with `provider_name:
"turfbuild/turf"`) and run as gating `invoke` effects at apply — the human gate
before the create, the agent check after it.

## How they resolve

- **`turf_confirm`** requires a client that advertises MCP **elicitation**; the
  client renders a two-choice control whose negative option names the trigger's
  `on_failure` (Halt / Taint (replace) / Proceed).
- **`turf_action`** requires a client that advertises MCP **sampling**; the agent
  performs the step and returns `{succeeded, detail, findings}`.
- When the client can't answer, each action's optional `non_interactive` config
  decides: `fail` (default — fail closed) or `skip` (treat as succeeded).

Describe either action's schema with `provider_describe action_type=turf_confirm`
(or `provider="turfbuild/turf"` to list them all).

## Prerequisites

- **Turf**, driven by a client that advertises MCP sampling + elicitation (the Turf
  CLI, or Claude Desktop). Turf runs the invoke effects and rounds the decisions
  through the client.
- No cloud account, no credentials.

## Usage

```bash
turf -C turf/language/turf-actions up
```

At apply, Turf asks you to approve the create, then asks the agent to run the
post-create verification.

## Cleanup

```bash
turf -C turf/language/turf-actions destroy
```
