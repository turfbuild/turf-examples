# Nodes in maintenance, declared

Which nodes are out of service is a set of names. Add a node to it, and it is
cordoned, drained, confirmed empty, handed to the agent for the repair, and
waited on until it reports Ready again. Take it out, and it is uncordoned.

```hcl
maintenance = ["worker-3"]
```

The steps are Terraform actions, run by `kubectl`
([`local_command`](https://registry.terraform.io/providers/hashicorp/local/latest/docs/actions/command)),
by [`turfbuild/kubewait`](https://registry.terraform.io/providers/turfbuild/kubewait),
which only reads, and by the agent driving Turf (`turf_action`). A
`terraform_data` instance per node records that the node is in maintenance,
and its lifecycle triggers run the steps.

Written for any cluster with a worker to spare; the Turf guide runs it on the
cluster [`use-cases/datacenter/aicr-stack`](../../../use-cases/datacenter/aicr-stack/README.md)
creates with `worker_count = 2`.

## In plain terms

Node maintenance is usually a runbook: `kubectl cordon`, `kubectl drain`, check
the node is empty, do the work, check the node is healthy, `kubectl uncordon`.
Nothing records which nodes are mid-runbook, so a node can stay cordoned long
after anyone remembers why. And when the drain fails halfway, the node is left
cordoned and half-drained.

Here the set *is* the record. The plan says which nodes go in and which come
out. A failed step fails the run and marks the node as not done, so the next
run starts that node again from the cordon, and the others are untouched.

### The gist

`main.tf` is plain Terraform — cordon, drain, confirm:

```hcl
resource "terraform_data" "maintenance" {
  for_each = var.maintenance
  input    = each.key

  lifecycle {
    action_trigger {
      events = [after_create]
      actions = [
        action.local_command.cordon[each.key],
        action.local_command.drain[each.key],
        action.kubewait_condition.drained[each.key],
      ]
      on_failure = taint
    }
    action_trigger {
      events  = [before_destroy]
      actions = [action.local_command.release]
    }
  }
}
```

Each step is an action with one instance per node in the cluster, keyed by node
name (`for_each = local.nodes`, from `data.kubernetes_nodes.all`). The wait
selects the node's Pods with `field_selector = "spec.nodeName=…"` and filters
out what `kubectl drain` leaves behind, and what an eviction cannot keep off
the node:

```hcl
action "kubewait_condition" "drained" {
  for_each = local.nodes
  config {
    api_version    = "v1"
    kind           = "Pod"
    field_selector = "spec.nodeName=${each.key}"
    filter         = <<-CEL
      !(has(object.metadata.ownerReferences) && object.metadata.ownerReferences.exists(r, r.kind == 'DaemonSet')) &&
      !(has(object.metadata.annotations) && 'kubernetes.io/config.mirror' in object.metadata.annotations) &&
      !(has(object.status.phase) && object.status.phase in ['Succeeded', 'Failed']) &&
      !(has(object.spec.tolerations) && object.spec.tolerations.exists(t,
          (!has(t.key) || t.key == 'node.kubernetes.io/unschedulable') && (!has(t.operator) || t.operator == 'Exists')))
    CEL
    min_matching = 0
    max_matching = 0
    settle       = "10s"
    timeout      = "5m"
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

The two `turf_action`s read their node from `caller`, the instance whose step
they are, so one declaration serves every node in the set; the Ready wait is
keyed like the steps in `main.tf`, and in an overlay's trigger `each.key` is
the target instance's own.

A `turf_action` is the built-in action the agent driving Turf carries out
itself. The apply stops at `awaiting_actions` with the prompt and `inputs`; the
agent does the step with its own tools — asks the user, runs `kubectl describe
node` — and answers with `apply(action_results)`: `succeeded`, its `progress`,
and an `error` when it failed. A "no" to the window is a failure carrying the
user's reason, and the halt means the instance is never created: nothing was
cordoned.

## What This Demonstrates

- **Maintenance as a set.** `var.maintenance` lists the nodes held out of
  service; the plan shows which ones go in (`create`) and which come out
  (`destroy`), and on Turf `plan.invocations` lists every step in the order it
  will run.
- **Ordered steps.** A trigger's actions run in the order listed, and the first
  failure stops the rest. The `terraform_data` instance is not created until
  every step succeeds.
- **A typo fails the plan.** The steps are keyed by the cluster's node names,
  so a name that is not a node has no step to run: `Reference to non-existent
  action instance`, naming the address.
- **A failed drain is retried, not stranded.** `on_failure = taint` fails the
  run *and* taints the instance. The next plan replaces it, which runs the steps
  again. Without the taint (`halt`), the run still fails, but the instance is
  recorded as if the node were drained, and the next plan says "No changes".
- **A decision is the operator's.** The window gate asks before anything is
  touched. The agent never answers it for them.
- **The repair is the agent's.** In a datacenter it is the provider's host
  playbook; here the agent inspects the drained node and reports. Either way it
  is a step in the record, not a shell command nobody wrote down.
- **Re-certification is a wait.** `kubewait_condition.ready` holds until the
  node reports `Ready=True` for `settle`; a node that left the cluster fails it.
- **Leaving maintenance uncordons.** `release` runs on `before_destroy`, so an
  uncordon that fails keeps the instance, and the next run tries again.
- **The waits only observe.** `kubewait_condition` lists and watches. It
  confirms the drain and the recovery; it never deletes anything.
- **"Drained" means nothing an eviction can keep off the node.** A Pod that
  tolerates the cordon — a toleration with no key, or for
  `node.kubernetes.io/unschedulable` — is evicted by the drain and may be
  scheduled straight back, so the wait does not count it, as it does not count
  DaemonSet Pods. AICR's component defaults give its runtime operators exactly
  that toleration on every platform (the registry's `nodeScheduling`; a recipe
  narrows it with `--system-node-toleration`), so on an AICR cluster the drain
  moves the tenant's workloads and the runtime's own operators come back; the
  instance is what says the node is mid-runbook.

## What it does when you run it

Measured on Terraform 1.16.2 with `hashicorp/kubernetes` 3.3.0,
`hashicorp/local` 2.9.1 and `turfbuild/kubewait` 0.1.0, against a three-node
kind cluster (Kubernetes 1.36.1) running a six-replica Deployment. Terraform
never sees `maintenance.turf.hcl`, so these are the three `main.tf` steps; the
Turf run, with all six, is under [On Turf](#on-turf).

**Into maintenance.** One instance, three actions, in order:

```
Plan: 1 to add, 0 to change, 0 to destroy. Actions: 3 to invoke.

Action started: action.local_command.cordon["node-maint-worker"] (triggered by terraform_data.maintenance["node-maint-worker"])
node/node-maint-worker cordoned
Action started: action.local_command.drain["node-maint-worker"] (triggered by terraform_data.maintenance["node-maint-worker"])
evicting pod default/web-847f49cc4d-g5ksv
...
node/node-maint-worker drained
Action started: action.kubewait_condition.drained["node-maint-worker"] (triggered by terraform_data.maintenance["node-maint-worker"])
Action action.kubewait_condition.drained["node-maint-worker"] (...): success: no objects match · 10s elapsed, 4m50s left · success held 10s of 10s
terraform_data.maintenance["node-maint-worker"]: Creation complete after 11s
Apply complete! Resources: 1 added, 0 changed, 0 destroyed. Actions: 3 invoked.
```

The node's DaemonSet Pods (`kindnet`, `kube-proxy`) stay, and the wait does not
count them. `kubectl drain` already waits for the Pods it evicts to be deleted,
so here the wait passes at once and holds for `settle`. It earns its keep when
something else is running on the node: a Pod that lands after the drain, or a
drain configured not to wait.

**A drain that fails.** With a PodDisruptionBudget allowing no evictions and
`--timeout=20s` in `drain_flags`, the drain fails, the wait never runs, the run
exits 1, and the instance is tainted. The node stays cordoned:

```
Action failed: action.local_command.drain["node-maint-worker2"] (...) - Command Execution Failed
# terraform_data.maintenance["node-maint-worker2"]: (tainted)
```

After the budget is removed, the next plan replaces the instance, and the steps
run again from the cordon:

```
  # terraform_data.maintenance["node-maint-worker2"] is tainted, so must be replaced
Plan: 1 to add, 0 to change, 1 to destroy. Actions: 4 to invoke.
```

The fourth action is `release`, on the old instance's destroy. While the node is
still in `var.maintenance`, `release` runs `true` instead of `kubectl uncordon`,
so the node is not uncordoned between the attempts. (A trigger `condition`
cannot do this: Terraform rejects `condition` on destroy events.)

**Out of maintenance.** Removing a name destroys its instance, and `release`
uncordons the node:

```
Plan: 0 to add, 0 to change, 1 to destroy. Actions: 1 to invoke.
node/node-maint-worker2 uncordoned
```

**A node that left the cluster.** A node deleted while in maintenance does not
break the plan; the instance stays as it is. Removing the name then releases a
node that is gone (measured with a Node object deleted mid-maintenance):

```
node/ghost is gone; nothing to uncordon
```

`release` reads the node from `caller`, the instance being destroyed, rather
than from a keyed instance, which is why it still has a node to name once the
cluster no longer lists it.

## Prerequisites

- **Terraform 1.16.0 or later, or Turf.** `on_failure` and destroy-event
  triggers first appear in 1.16; `maintenance.turf.hcl` runs on Turf only (the
  Turf CLI or any MCP client pointed at `turf-mcp-server`; see
  [Running the examples](../../../README.md#running-the-examples)).
- **An existing cluster with a worker to spare, and a kubeconfig**
  (`~/.kube/config` by default; override with `kubeconfig_path` /
  `kubeconfig_context`, `kind-aicr-1` for the AICR stack's cluster). The
  providers and `kubectl` all use it. With one worker beside a kind control
  plane every workload is on that worker and a drain has nowhere to move it.
- **`kubectl` on the `PATH`** of the process running Terraform, or of the Turf
  engine (the Homebrew service's, with Homebrew's `PATH`): `local_command`
  runs it there, not in your shell.

## Usage

```bash
cd terraform/kubernetes/node-maintenance
cp terraform.tfvars.example terraform.tfvars   # set kubeconfig_context; maintenance = ["<node>"]
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

On Turf, `turf -C . up`; through the MCP tools the same run is `init`,
`open`, `up`, then `plan` and `apply` each round (answering each
`awaiting_actions` pause with `action_results`), until `converged`.

`drain_flags` defaults to `--ignore-daemonsets --delete-emptydir-data
--timeout=10m`. A Pod that no controller owns blocks `kubectl drain` unless
you add `--force`. A PodDisruptionBudget that allows no evictions blocks it
until the timeout — the failed-drain case above.

## Verify

```bash
terraform output in_maintenance      # or `turf -C . output in_maintenance`, or the MCP `output` tool
kubectl get nodes
kubectl get pods -A --field-selector spec.nodeName=<node>
```

## Cleanup

End maintenance by emptying the set, then apply:

```hcl
maintenance = []
```

Don't end it with `terraform destroy` while the set still lists nodes. To the
uncordon, a destroy looks like a retry, because the node is still in
`var.maintenance`, so the nodes stay cordoned (measured).

## On Turf

The configuration runs on Turf unchanged, and Turf adds the overlay's two
steps. Measured with `turf-engine` at `dbea97e` (the change that admits a keyed
action reference in a trigger; opentofu fork `v1.12.6-turf.10`), driven through
the MCP tools against a fresh two-worker kind cluster running a four-replica
Deployment:

- **Into maintenance.** One create and six invocations, in order, the apply
  pausing twice for the agent — 32 s end to end, the drain moving the Pods to
  the other worker:

  ```
  create    terraform_data.maintenance["day2-keyed-worker"]
    invoke    action.turf_action.window  (before_create, on_failure = halt)        → awaiting_actions
    invoke    action.local_command.cordon["day2-keyed-worker"]  (after_create, on_failure = taint)
    invoke    action.local_command.drain["day2-keyed-worker"]
    invoke    action.kubewait_condition.drained["day2-keyed-worker"]
    invoke    action.turf_action.repair                                           → awaiting_actions
    invoke    action.kubewait_condition.ready["day2-keyed-worker"]
  round 1: applied (applied 1, invoked 6)
  ```

- **A second node.** Adding a name while the first stays plans one create and
  that node's six steps; the first instance is not touched. Taking one name out
  while the other stays plans one destroy and one `release`, that node's.
- **A drain that fails.** Under the same budget the drain fails after its
  timeout, nothing after it runs, the run ends `failed`, and the instance is
  tainted. Once the budget is removed, the next `up` replaces the instance with
  seven invocations: the six steps and `release` on the old instance's destroy,
  the no-op.
- **A node that left the cluster.** With a Node object deleted mid-maintenance,
  the next plan leaves its instance alone, as Terraform does. Removing the name
  runs `release`, which finds nothing to uncordon.
- **A typo fails the plan**, in Terraform's words:

  ```
  terraform_data.maintenance["nope"]: Reference to non-existent action instance: The address action.local_command.cordon["nope"] does not identify an instance of action.local_command.cordon
  ```

Three rules of the keyed form, each witnessed against Terraform 1.16 and kept
by the engine: a key the actions do not have fails the plan (as above); an
instance whose key has left the actions plans clean while it is unchanged, and
a destroy trigger that named a keyed step on such an orphan would warn
("Orphaned action failed to plan") and invoke none of its actions — `release`
reads `caller`, not a key, which is why it still runs; and `each.key` in an
overlay's trigger is the target instance's, so `maintenance.turf.hcl` binds
every instance to its own node's Ready wait without naming any. The typo check
is the plan's, in Terraform's words, rather than a friendlier one. A
`precondition` would not fit: it is read on every plan for every instance, so a
node that left the cluster while in maintenance would fail every plan until its
name was removed. A `check` block would, as a warning, and Turf does not take
`check` blocks yet.

## Appendix: the imperative alternative, actions only

The same steps can run with no `terraform_data` at all: invoke each node's
actions by hand. The keyed actions in `main.tf` serve both, and `invoke.tf` adds
a keyed `uncordon` for this path.

```bash
N=worker-3
terraform plan "-invoke=action.local_command.drain[\"$N\"]" -out=tfplan        && terraform apply tfplan
terraform plan "-invoke=action.kubewait_condition.drained[\"$N\"]" -out=tfplan && terraform apply tfplan
# ...the maintenance...
terraform plan "-invoke=action.local_command.uncordon[\"$N\"]" -out=tfplan     && terraform apply tfplan
```

`kubectl drain` cordons first, so there is no separate cordon step. Measured on
the same cluster:

- **One action per plan.** Terraform refuses a second `-invoke`: "Only one
  action can be invoked at a time". A maintenance is three plans and three
  applies per node.
- **Each plan file pins its step.** `terraform show -json tfplan` lists the
  invocation under `action_invocations`, with its arguments resolved, and the
  file applies once.
- **A wrong name still fails the plan**, because the instance does not exist:
  `invoked target … not found`.
- **Nothing is recorded.** After all three steps, state holds only the data
  source. Which nodes are cordoned, and why, lives in the cluster and in
  whoever ran the commands.

On Turf the equivalent is `invoke`, which takes the same addresses (the MCP
tool's `action_addr`, or `turf-driver invoke --auto-approve . 'action.local_command.drain["worker-3"]'`).
Measured on the same cluster, the drain, the wait and the uncordon each ran as
one invoke of 16 to 26 s, and a misspelled instance failed the plan with
`invoked target … not found`.

Don't invoke `release`. It reads `caller`, which only a trigger defines, yet
`-invoke` does not refuse it: Terraform 1.16.2 fills `caller` from an instance
in state, the first one, and that node would be uncordoned.

| | Declared (`var.maintenance`) | Imperative (`-invoke`) |
|---|---|---|
| Which nodes are in maintenance | the set, and one instance per node in state | nowhere |
| Runs per node | one plan for any number of nodes | three plans and three applies |
| A failed drain | the run fails, the instance is tainted, and the next run starts over | the step fails; what next is up to you |
| Back in service | remove the name | invoke `uncordon` |
| What reviewing the plan shows | every node going in or out | one step on one node |
