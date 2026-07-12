# Two-phase (staged-then-commit) apply

> **Advanced / stretch example.** It *models* a two-phase provider using a mock
> provider and Terraform Actions — it does not drive a real device. See "What this
> is (and isn't)" below.

Some systems don't apply a change the moment you declare it. They **stage** a
candidate change, then require an explicit, atomic **commit** to make it live:

- network devices — stage a candidate config, then `commit` (JunOS, PAN-OS, …);
- some databases — stage a migration, then run it;
- feature-flag / config services — stage, then publish.

This example shows the Terraform idiom for that shape: a **resource that stages** the
change plus an **`after_create`/`after_update` action that commits** it.

## What This Demonstrates

`tfcoremock_simple_resource.candidate` carries the staged config; a `commit` action is
triggered `after_create` and `after_update` (see `main.tf`). Turf orders them as:

```
create(candidate)  →  invoke(commit)
update(candidate)  →  invoke(commit)
```

The commit action's default `on_failure = halt` is the **atomic-commit boundary**: if
the commit fails, the run stops rather than leaving downstream changes half-applied.

## What this is (and isn't)

- **Is:** the *actions-as-commit* pattern, expressed in ordinary HCL and runnable with a
  public provider. Swap `tfcoremock` for a real device provider and the `commit` action
  for that provider's real commit/publish action, and the structure is identical.
- **Isn't:** a real device integration, and not a demonstration of Turf splitting the
  stage and commit across separate convergence *phases*. For a genuine **cross-phase**
  provider workflow — where a later step can't even be planned until an earlier one is
  applied, and Turf converges it automatically — see
  [`../../kubernetes/kind-crd`](../../kubernetes/kind-crd) (cluster → CRD → custom
  resource in one run).

## Prerequisites

- **Turf** (the Turf CLI or any MCP client pointed at `turf-mcp-server`).
- No cloud account, no credentials.

## Usage

```bash
turf -C terraform/language/two-phase up
```

Then change `candidate_config` and re-run to see the `update` → `commit` sequence.

## Cleanup

```bash
turf -C terraform/language/two-phase destroy
```
