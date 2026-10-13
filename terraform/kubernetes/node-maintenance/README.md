# A node in maintenance, declared

Which node is out of service is a set with one name. Put the node in it, and
it is cordoned, drained, confirmed empty, handed to the agent for the repair,
and waited on until it reports Ready again. Take it out, and it is uncordoned.

```hcl
maintenance = ["aicr-1-worker"]
```

The steps are Terraform actions, run by `kubectl`
([`local_command`](https://registry.terraform.io/providers/hashicorp/local/latest/docs/actions/command)),
by [`turfbuild/kubewait`](https://registry.terraform.io/providers/turfbuild/kubewait),
which only reads, and by the agent driving Turf (`turf_action`). A
`terraform_data` record per node in maintenance says the node is mid-runbook,
and its lifecycle triggers run the steps.

Written for the cluster
[`use-cases/datacenter/aicr-stack`](../../../use-cases/datacenter/aicr-stack/README.md)
creates with `worker_count = 2`, and for any cluster with a worker to spare.

## In plain terms

Node maintenance is usually a runbook: `kubectl cordon`, `kubectl drain`, check
the node is empty, do the work, check the node is healthy, `kubectl uncordon`.
Nothing records which nodes are mid-runbook, so a node can stay cordoned long
after anyone remembers why; and when the drain fails halfway, the node is left
cordoned and half-drained.

Here the set *is* the record. The plan says whether the node goes in or comes
out. A failed step fails the run and marks the node as not done, so the next
run starts again from the cordon.

### The gist

`main.tf` is plain Terraform — cordon, drain, confirm:

```hcl
resource "terraform_data" "maintenance" {
  for_each = var.maintenance
  input    = each.key

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.local_command.cordon, action.local_command.drain,
                 action.kubewait_condition.drained]
      on_failure = taint
    }
    action_trigger {
      events  = [before_destroy]
      actions = [action.local_command.release]
    }
  }
}
```

`maintenance.turf.hcl` is Turf's: the two steps a person or the agent performs.
tofu and terraform ignore the file by its name; Turf lays it over `main.tf` at
every plan, splicing its triggers after the resource's own, so the whole
runbook runs as **window → cordon → drain → drained → repair → ready**:

```hcl
action "turf_action" "window" {
  config { prompt = "Ask the user whether the maintenance window for node ${var.node} is open now. …" }
}
action_trigger "window" {
  target     = terraform_data.maintenance
  events     = [before_create]
  actions    = [action.turf_action.window]
  on_failure = halt
}

action "turf_action" "repair" {
  config { prompt = "Node ${var.node} is cordoned and drained. Inspect it … Fail if the node is NotReady or missing." }
}
action_trigger "repair_and_recertify" {
  target     = terraform_data.maintenance
  events     = [after_create]
  actions    = [action.turf_action.repair, action.kubewait_condition.ready]
  on_failure = taint
}
```

A `turf_action` is the built-in action the agent driving Turf carries out
itself. The apply stops at `awaiting_actions` with the prompt and `inputs`; the
agent does the step with its own tools — asks the user, runs `kubectl describe
node` — and answers with `apply(action_results)`: `succeeded`, its `progress`,
and an `error` when it failed. A "no" to the window is a failure carrying the
user's reason, and the halt means the record is never created: nothing was
cordoned.

## What this demonstrates

- **Maintenance as a record.** `var.maintenance` names the node held out of
  service; the plan shows it going in (`create`) or coming out (`destroy`), and
  `plan.invocations` lists every step in the order it will run.
- **A decision is the operator's.** The window gate asks before anything is
  touched. The agent never answers it for them.
- **Ordered steps, one failure stops the rest.** The record is not created
  until every step succeeds. `on_failure = taint` on both chains fails the run
  *and* taints the record, so the next plan replaces it and the steps run
  again from the cordon. Without the taint (`halt`), the run still fails, but
  the record is kept as if the node were done, and the next plan says
  "No changes".
- **The repair is the agent's.** In a datacenter it is the provider's host
  playbook; here the agent inspects the drained node and reports. Either way it
  is a step in the record, not a shell command nobody wrote down.
- **Re-certification is a wait.** `kubewait_condition.ready` holds until the
  node reports `Ready=True` for `settle`; a node that left the cluster fails it.
- **Leaving maintenance uncordons.** `release` runs on `before_destroy`, so an
  uncordon that fails keeps the record, and the next run tries again. It reads
  the node from `caller`, the record being destroyed, so a node that has since
  left the cluster is released without error ("nothing to uncordon").
- **The waits only observe.** `kubewait_condition` lists and watches; it never
  deletes anything.
- **"Drained" means nothing an eviction can keep off the node.** A pod that
  tolerates the cordon — a toleration with no key, or for
  `node.kubernetes.io/unschedulable` — is evicted by the drain and may be
  scheduled straight back, so the wait does not count it, as it does not count
  DaemonSet pods. The AICR kind recipe gives every operator exactly that
  toleration (its overlay is written for nvkind), so on that cluster the drain
  moves little and the record is what matters; on a datacenter cluster the
  workloads move.

## Prerequisites

- **Turf** (the Turf CLI or any MCP client pointed at `turf-mcp-server`; see
  [Running the examples](../../../README.md#running-the-examples)).
- **A cluster with a worker to drain and a kubeconfig** (`~/.kube/config` by
  default; `kubeconfig_context = "kind-aicr-1"` for the AICR stack's cluster).
  With one worker beside a kind control plane every workload is on that worker
  and a drain has nowhere to move it, so the AICR stack's `worker_count = 2`.
- **`kubectl` on the `PATH` of the engine** (the Homebrew service's, with
  Homebrew's `PATH`): `local_command` runs it there, not in your shell.

## Usage

```bash
cd terraform/kubernetes/node-maintenance
cp terraform.tfvars.example terraform.tfvars   # set node, kubeconfig_context; maintenance = []
turf -C . up                                   # nothing to do yet; registers the state
```

Put the node in maintenance — `maintenance = ["aicr-1-worker"]` — and `up`
again: one add, six invocations. The apply stops for the window, runs the
cordon, the drain and the drained check, stops again for the repair, and waits
for Ready. Through the MCP tools the same run is `init`, `workspace_open`,
`up`, `apply` (answering each `awaiting_actions` pause with `action_results`),
until `converged`.

`drain_flags` defaults to `--ignore-daemonsets --delete-emptydir-data
--timeout=10m`. A Pod that no controller owns blocks `kubectl drain` unless
you add `--force`. A PodDisruptionBudget that allows no evictions blocks it
until the timeout — which is the failed-drain case below.

Back in service: `maintenance = []`, `up` — one destroy, and `release`
uncordons the node.

## Verify

```bash
turf -C . output in_maintenance      # or the MCP `output` tool
kubectl --context kind-aicr-1 get nodes
kubectl --context kind-aicr-1 get pods -A --field-selector spec.nodeName=aicr-1-worker
```

## A drain that fails

With a PodDisruptionBudget allowing no evictions and `--timeout=20s` in
`drain_flags`, the drain fails, nothing after it runs, the run ends `failed`
and the record is tainted. The node stays cordoned. Remove the budget and `up`
again: the plan replaces the record and the steps run again from the cordon,
with `release` a no-op on the old record's destroy (the node is still in
`var.maintenance`, so the uncordon is skipped between attempts).

## Cleanup

End maintenance by emptying the set, then `up`. Don't end it with `destroy`
while the set still names the node: to the uncordon, a destroy looks like a
retry, so the node stays cordoned.

## On Turf

This is the one-node form of a general example. Keyed by node name — a
`for_each` over the cluster's nodes with each record picking its own actions by
`action.local_command.cordon[each.key]` — the same configuration maintains any
number of nodes from one set. Turf's engine does not take that form yet: it
accepts an action reference in a trigger only with a constant key, and stops at
the first `[each.key]`:

```
main.tf:31,9-46: Invalid expression; A single static variable reference is required: only attribute access and indexing with constant keys.
```

So the node is named once (`var.node`), the actions are single, and
`var.maintenance` may only hold that name (a validation says so). The engine
does not take resource `precondition`s either, so a wrong node name fails at
the cordon rather than at the plan. Everything
else — the keyed `terraform_data`, the ordered chain, `on_failure = taint` on
a failed drain, the replace that retries it with `release` a no-op, `release`
through `caller` on removal, and the overlay's steps — runs on the engine as
written. The keyed trigger reference is on the engine's backlog.

Plain Terraform 1.16 runs `main.tf` on its own: cordon, drain, confirm, and
uncordon on the way out. It never sees `maintenance.turf.hcl`.
