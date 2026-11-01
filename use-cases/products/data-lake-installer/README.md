# A product's installer, as a configuration

A product that needs cloud infrastructure ships a deployment guide and sends a
solutions engineer. This directory is the other way: the product ships its
reference architecture as an ordinary Terraform configuration — here a small
data lake on AWS — plus one file of its own steps, and the customer's agent, or
the product's own, installs it in the customer's account, on plan.

**Plan-only by default, with no credentials.** `plan_only = true` configures
the AWS provider with mock keys and every configure-time API call skipped, so a
create-only plan runs on a laptop with no account at all — the plan is the
install's contract, read before anything exists. A customer sets
`plan_only = false` and the same plan applies with their credentials. (The
variable is this configuration's own; turf's `plan_only` argument on `up`, which
ends a run with its plan kept as a planfile, is a different thing.)

## What this demonstrates

- **The questionnaire is `init`.** What `init` reports under `variables[]`
  with no default — `product_name`, `tenant`, `region` — is what the customer
  supplies. Everything else is the product's.
- **A reference architecture, read as one plan.** A VPC and two private
  subnets, a raw and a curated bucket with public access blocked, a Glue
  catalog database, an Athena workgroup, and the role they assume. One `up`,
  one `plan`, every resource in it, and not one API call.
- **The installer's own steps ride with it.** `installer.turf.hcl` — tofu and
  terraform ignore it by its name; Turf lays it over the configuration at
  every plan — declares three `turf_action`s, the built-in action the agent
  driving Turf carries out itself (the apply stops at `awaiting_actions`, the
  agent does the step, and answers with `apply(action_results)`):
  - `verify_private`, `after_create` on each bucket: read its public access
    block back and fail unless all four settings hold; a failure taints the
    bucket.
  - `welcome`, `after_create` on the workgroup: tell the customer the lake is
    ready; a failed notice only warns (`on_failure = continue`).
  - `consent`, `before_destroy` on the catalog: ask the customer before their
    data catalog is removed; a "no" is a failure carrying their reason, and the
    halt means it stays.
- **Unattended, governed.** An installer that runs by itself approves each
  round's plan itself (`apply` with its digest), or applies a planfile someone
  else planned and read (turf's `plan_only` argument, then `apply({ planfile })`,
  perhaps from a server whose tier can only apply) — and the three steps above
  still stop it: they are the author's, not the approver's.
- **Run a step without an account.** `consent` is declared, so it can be put to
  the customer on demand: `invoke({ action_addr: "action.turf_action.consent" })`
  starts it, `plan` plans the invocation and stops for approval, and on `apply`
  it asks.

## Prerequisites

- **Turf** (the Turf CLI or any MCP client pointed at `turf-mcp-server`; see
  [Running the examples](../../../README.md#running-the-examples)).
- Nothing else for the plan. An AWS account and credentials in the engine's
  environment for an apply (`plan_only = false`).

Resources rather than the registry's VPC module, on purpose: `invoke` evaluates
the whole configuration against the state, and a module's count-indexed
resources have no instances to index before they exist — so the on-demand
`consent` above would fail on an empty state. Plain resources evaluate as
unknown and the step runs.

## Usage

```bash
cd use-cases/products/data-lake-installer
cp terraform.tfvars.example terraform.tfvars   # product_name, tenant, region
turf -C . up                                   # plan only: read it, then decline
```

Through the MCP tools: `init`, `open`, `up({ var: {…}, plan_only: true })` (turf's
argument, not the variable: the run plans one round and ends `planned`), then
`plan({ convergence_id, refresh: false })`, and read the plan with `show`. Nothing
is applied and nothing is left waiting; the planfile it keeps expires by itself.
`plan.invocations` lists the three steps beside the creates.

## Cleanup

Nothing was created, and a declined or plan-only run leaves nothing waiting:
`close`.
With `plan_only = false` and a real apply, `destroy` starts the teardown — and
`consent` asks the customer before the catalog goes.
