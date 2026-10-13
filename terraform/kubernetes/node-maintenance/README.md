# Nodes in maintenance, declared

Which nodes are out of service is a set of names. Put a node in it, and it is
cordoned, drained, confirmed empty, handed to the agent for the repair, and
waited on until it reports Ready again. Take it out, and it is uncordoned.

```hcl
maintenance = ["aicr-1-worker", "aicr-1-worker2"]
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

Here the set *is* the record. The plan says which node goes in and which comes
out. A failed step fails the run and marks that node as not done, so the next
run starts it again from the cordon, and the others are untouched.

### The gist

`main.tf` is plain Terraform — cordon, drain, confirm, each record picking its
own node's step by key:

```hcl
resource "terraform_data" "maintenance" {
  for_each = var.maintenance
  input    = each.key

  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.local_command.cordon[each.key], action.local_command.drain[each.key],
                 action.kubewait_condition.drained[each.key]]
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
  config { prompt = "Ask the user whether the maintenance window for node ${caller.input} is open now. …" }
}
action_trigger "window" {
  target     = terraform_data.maintenance
  events     = [before_create]
  actions    = [action.turf_action.window]
  on_failure = halt
}

action "turf_action" "repair" {
  config { prompt = "Node ${caller.input} is cordoned and drained. Inspect it … Fail if the node is NotReady or missing." }
}
action_trigger "repair_and_recertify" {
  target     = terraform_data.maintenance
  events     = [after_create]
  actions    = [action.turf_action.repair, action.kubewait_condition.ready[each.key]]
  on_failure = taint
}
```

The two `turf_action`s read their node from `caller`, the record whose step
they are, so one declaration serves every node in the set; the Ready wait is
keyed like the steps in `main.tf`, and in an overlay's trigger `each.key` is
the target record's own.

A `turf_action` is the built-in action the agent driving Turf carries out
itself. The apply stops at `awaiting_actions` with the prompt and `inputs`; the
agent does the step with its own tools — asks the user, runs `kubectl describe
node` — and answers with `apply(action_results)`: `succeeded`, its `progress`,
and an `error` when it failed. A "no" to the window is a failure carrying the
user's reason, and the halt means the record is never created: nothing was
cordoned.

## What this demonstrates

- **Maintenance as a record.** `var.maintenance` names the nodes held out of
  service; the plan shows each going in (`create`) or coming out (`destroy`),
  and `plan.invocations` lists every step in the order it will run.
- **Each record runs its own node's steps.** The actions are keyed by the
  cluster's node names and each record picks its key's instance, so a name
  that is not a node has no step and fails the plan, before anything is
  touched.
- **A decision is the operator's.** The window gate asks before anything is
  touched. The agent never answers it for them.
- **Ordered steps, one failure stops the rest.** A record is not created
  until every step succeeds. `on_failure = taint` on both chains fails the run
  *and* taints the record, so the next plan replaces it and the steps run
  again from the cordon; a record whose steps all passed is left alone. Without the taint (`halt`), the run still fails, but
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
  DaemonSet pods. AICR's component defaults give its runtime operators exactly
  that toleration on every platform (the registry's `nodeScheduling`; a recipe
  narrows it with `--system-node-toleration`), so on an AICR cluster the drain
  moves the tenant's workloads and the runtime's own operators come back; the
  record is what says the node is mid-runbook.

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
cp terraform.tfvars.example terraform.tfvars   # set kubeconfig_context; maintenance = []
turf -C . up                                   # nothing to do yet; registers the state
```

Put a node in maintenance — `maintenance = ["aicr-1-worker"]` — and `up`
again: one add, six invocations. The apply stops for the window, runs the
cordon, the drain and the drained check, stops again for the repair, and waits
for Ready. Through the MCP tools the same run is `init`, `workspace_open`,
`up`, `apply` (answering each `awaiting_actions` pause with `action_results`),
until `converged`. Name two nodes and the plan is two adds, twelve
invocations; each record's steps are its own node's, and the apply asks the
window for each.

`drain_flags` defaults to `--ignore-daemonsets --delete-emptydir-data
--timeout=10m`. A Pod that no controller owns blocks `kubectl drain` unless
you add `--force`. A PodDisruptionBudget that allows no evictions blocks it
until the timeout — which is the failed-drain case below.

Back in service: take the name out, `up` — one destroy, and `release`
uncordons the node. The other names in the set are not touched.

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

The whole example runs on Turf's engine as written: the keyed steps, the
ordered chain, `on_failure = taint` on a failed drain, the replace that retries
it with `release` a no-op, `release` through `caller` on removal, and the
overlay's two `turf_action`s between them. Three rules of the keyed form, each
witnessed against Terraform 1.16 and kept by the engine:

- **A key the actions do not have fails the plan.** `maintenance = ["typo"]`
  is refused at plan with the instance it could not find; nothing runs. (A
  `precondition` on the record could say the same in friendlier words; the
  engine does not take resource conditions yet.)
- **A record whose node has left the cluster is left alone**, and plans clean
  while its name stays in the set. Take the name out and `release` runs on
  its destroy — it reads the node from `caller`, not from a key — and finds
  nothing to uncordon. Had the destroy trigger named a keyed step, the record
  would be an orphan whose key the actions no longer have: Terraform warns
  ("Orphaned action failed to plan") and invokes none of its actions, and so
  does the engine.
- **`each.key` in an overlay's trigger is the target record's**, so
  `maintenance.turf.hcl` binds every record to its own node's Ready wait
  without naming any.

Plain Terraform 1.16 runs `main.tf` on its own: cordon, drain, confirm, and
uncordon on the way out. It never sees `maintenance.turf.hcl`.
