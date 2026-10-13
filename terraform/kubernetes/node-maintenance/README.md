# Nodes in maintenance, declared

Which nodes are out of service is a set of names. Add a node to it, and it is
cordoned, drained, and confirmed empty. Take it out, and it is uncordoned.

```hcl
maintenance = ["worker-3"]
```

The steps are Terraform actions, run by `kubectl` and
[`turfbuild/kubewait`](https://registry.terraform.io/providers/turfbuild/kubewait),
which only reads. A `terraform_data` instance per node records that the node is
in maintenance, and its lifecycle triggers run the steps.

## In plain terms

Node maintenance is usually a runbook: `kubectl cordon`, `kubectl drain`, check
the node is empty, do the work, `kubectl uncordon`. Nothing records which nodes
are mid-runbook, so a node can stay cordoned long after anyone remembers why.
And when the drain fails halfway, the node is left cordoned and half-drained.

Here the set *is* the record. The plan says which nodes go in and which come
out. A failed drain fails the run and marks the node as not done, so the next
run starts that node again from the cordon.

### The gist

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
out what `kubectl drain` leaves behind:

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
      !(has(object.status.phase) && object.status.phase in ['Succeeded', 'Failed'])
    CEL
    min_matching = 0
    max_matching = 0
    settle       = "10s"
    timeout      = "5m"
  }
}
```

## What This Demonstrates

- **Maintenance as a set.** `var.maintenance` lists the nodes held out of
  service; the plan shows which ones go in (`create`) and which come out
  (`destroy`).
- **Ordered steps.** A trigger's actions run in the order listed, and the first
  failure stops the rest. The `terraform_data` instance is not created until
  all three steps succeed.
- **A typo fails the plan.** The steps are keyed by the cluster's node names,
  so a name that is not a node has no step to run: `Reference to non-existent
  action instance`, naming the address.
- **A failed drain is retried, not stranded.** `on_failure = taint` fails the
  run *and* taints the instance. The next plan replaces it, which runs the steps
  again. Without the taint (`halt`), the run still fails, but the instance is
  recorded as if the node were drained, and the next plan says "No changes".
- **Leaving maintenance uncordons.** `release` runs on `before_destroy`, so an
  uncordon that fails keeps the instance, and the next run tries again.
- **The wait only observes.** `kubewait_condition` lists and watches Pods. It
  confirms the drain; it never deletes anything.

## What it does when you run it

Measured on Terraform 1.16.2 with `hashicorp/kubernetes` 3.3.0,
`hashicorp/local` 2.9.1 and `turfbuild/kubewait` 0.1.0, against a three-node
kind cluster (Kubernetes 1.36.1) running a six-replica Deployment.

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

- **Terraform 1.16.0 or later.** `on_failure` and destroy-event triggers first
  appear there.
- **An existing cluster and a kubeconfig** (`~/.kube/config` by default;
  override with `kubeconfig_path` / `kubeconfig_context`). The providers and
  `kubectl` all use it.
- **`kubectl` on the `PATH`** of the process running Terraform:
  `local_command` runs it.

## Usage

```bash
cd terraform/kubernetes/node-maintenance
cp terraform.tfvars.example terraform.tfvars   # set maintenance = ["<node>"]
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

`drain_flags` defaults to `--ignore-daemonsets --delete-emptydir-data
--timeout=10m`. A Pod that no controller owns blocks `kubectl drain` unless
you add `--force`.

## Verify

```bash
terraform output in_maintenance
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

The configuration runs on Turf unchanged. Measured with `turf-engine` at
`d67b1db` plus the change that admits keyed action references in a trigger
(opentofu fork `v1.12.6-turf.10`), driven by `turf-driver up --converge`, on a
fresh cluster of the same shape. Each story above gave the same plan and the
same actions:

- **Into maintenance.** One create and three actions in order, 39 s end to end:

  ```
  create    terraform_data.maintenance["node-maint-worker"]
    invoke    action.local_command.cordon["node-maint-worker"]  (after_create, on_failure = taint)
    invoke    action.local_command.drain["node-maint-worker"]  (after_create, on_failure = taint)
    invoke    action.kubewait_condition.drained["node-maint-worker"]  (after_create, on_failure = taint)
  round p-fb103d75: applied (applied 1, failed 0, cancelled 0, invoked 3)
  ```

- **A drain that fails.** Under the same budget the drain fails, the wait does
  not run, the run exits 1, and the instance is tainted. Once the budget is
  removed, the next `up` replaces the instance with four actions, `release` the
  no-op among them. No cancel is needed between the two runs.
- **Out of maintenance.** One delete, and `release` prints
  `node/node-maint-worker2 uncordoned`.
- **A node that left the cluster.** With `ghost` deleted, the next plan leaves
  its instance alone, as Terraform does. Removing the name runs `release`,
  which prints `node/ghost is gone; nothing to uncordon`.
- **A typo fails the plan**, in Terraform's words:

  ```
  terraform_data.maintenance["node-maint-workr"]: Reference to non-existent action instance: The address action.local_command.cordon["node-maint-workr"] does not identify an instance of action.local_command.cordon
  ```

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

On Turf the equivalent is `turf-driver invoke`, which takes the same addresses
(`turf-driver invoke --auto-approve . 'action.local_command.drain["worker-3"]'`).
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
