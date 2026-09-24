# `kubewait_condition`: a Terraform action that waits on Kubernetes state

**Status: specified, not implemented.** This example declares five of these
actions, and `terraform validate` type-checks each against the schema below.
That works because the local provider name `kubewait` is bound to
`hashicorp/tfcoremock` 0.6.0-beta2, which serves `dynamic_resources.json` as an
action type (see `versions.tf`). tfcoremock only echoes the config back, so
everything here about *behaviour* is specification.

## Why an action

Some edges in this graph are about the state of an object, not its existence:
- a Certification that has *finished*;
- nodes that are Ready *and* no longer cordoned by nodewright;
- a namespace with *no* TrainJobs left in it.

Today each of those is a shell polling loop in AICR's CI. The obvious Terraform
alternatives don't express them:

| | Failure predicate | Settle window | Set / count / drain | Progress | Runs at |
| --- | --- | --- | --- | --- | --- |
| `helm_release.wait` | no | no | workloads only, never CR status | no | apply |
| `kubernetes_manifest` `wait {}` | no: a failed Certification waits out the whole timeout | no | no | no | apply, and needs API access at plan time |
| `local-exec` + `kubectl wait` | exit code only | no | no | no | create only, outside the graph |
| **`kubewait_condition`** | yes | yes | yes | streamed | **any lifecycle event** |

The last column matters most. An action can be attached to any lifecycle event.
It can gate a create (`before_create`), hold a resource's dependents
(`after_create`), hold a teardown (`before_destroy`), or confirm that one
happened (`after_destroy`). The same primitive covers bring-up and teardown.

## Provider

`turfbuild/kubewait` (placeholder address). The provider configuration is the
kubernetes provider's connection schema: `host`, `cluster_ca_certificate`,
`exec {}`, `config_path`, `config_context`, and so on. `providers.tf` shows it
commented beside the stand-in.

The action is read-only. It never creates, patches or deletes anything.

## Configuration

| Attribute | Type | Default | Meaning |
| --- | --- | --- | --- |
| `api_version` | string | required | Group/version of the kind to observe, e.g. `nvcre.nvidia.com/v1alpha1`. |
| `kind` | string | required | e.g. `Certification`, `Node`, `TrainJob`. |
| `namespace` | string | null | Omit for cluster-scoped kinds. For namespaced kinds in set mode, omitting it means all namespaces. |
| `name` | string | null | Set: **single-object mode**. Unset: **set mode**. |
| `label_selector`, `field_selector` | string | null | Server-side selection (set mode). |
| `filter` | CEL, over `object` | null | Client-side narrowing of the selected set. |
| `success_conditions` | list of `{type, status, reason?}` | [] | **All** must hold on an object for it to pass. |
| `failure_conditions` | list of `{type, status, reason?}` | [] | **Any** holding on any matched object is a failure. |
| `expression` | CEL, over `object` | null | ANDed with `success_conditions`. |
| `failure_expression` | CEL, over `object` | null | ORed with `failure_conditions`. |
| `set_expression` | CEL, over `objects` | null | A predicate on the whole matched set (set mode). |
| `min_matching` / `max_matching` | number | 1 / unbounded | Bounds on the number of *passing* objects. `max_matching = 0` with no success predicate is a **drain**. |
| `require_all` | bool | false | Every matched object must pass, not just `min_matching` of them. |
| `absent` | `pending` \| `success` \| `failure` | `pending` | Single-object mode: what a missing object counts as. |
| `timeout` | duration | **required** | Expiry is a failure. Nothing waits forever (AICR ADR-025 decision 6). |
| `settle` | duration | `0s` | A verdict must hold continuously this long before it counts. Any flip resets the clock. |
| `poll_interval` | duration | `10s` | Resync interval. |
| `watch` | bool | true | Watch between polls. |
| `progress_fields` | list(string) | [] | Field paths reported with each progress event. |
| `progress_interval` | duration | `60s` | Heartbeat interval between progress events when nothing changes. |

`ValidateActionConfig` rejects at plan time:
- `name` together with a selector;
- `min_matching > max_matching`;
- `settle >= timeout`;
- CEL that does not compile;
- a drain (`max_matching = 0`) that also has success predicates.

## Evaluation

A condition entry `{type, status, reason?}` matches an object when its
`status.conditions` has an entry of that `type` with that `status`, and, if
`reason` is given, that `reason`. There is no special treatment of
`status.phase`: use `expression` for it.

**Single-object mode** (`name` set):
- **success:** the object exists, every success predicate holds, and no failure predicate holds;
- **failure:** any failure predicate holds, or the object is absent and `absent = "failure"`;
- otherwise **pending**.

**Set mode:**
- *matched* = objects selected by the selectors, narrowed by `filter`;
- *passing* = matched objects satisfying the success predicates (all matched objects if there are none).

Then:
- **success:** `min_matching ≤ |passing| ≤ max_matching`, and (`require_all` ⇒ passing = matched), and `set_expression` holds;
- **failure:** any matched object satisfies a failure predicate;
- otherwise **pending**.

**Failure wins ties.** A verdict must survive `settle` before it counts. The
wait ends at the first settled success or failure, or at `timeout`.

API errors are retried until `timeout`. The exceptions are 401 and 403, which
fail at once: waiting will not fix them.

## Semantics per trigger event

| Event | Role | Effect of a failed wait |
| --- | --- | --- |
| `before_create`, `before_update` | **Gate.** Observes the cluster before the resource's create or update. | The operation never runs. |
| `after_create`, `after_update` | **Hook.** Runs inside the resource's apply node, after the state write. | Dependents do not start. |
| `before_destroy` | **Gate** on teardown. | The delete never runs; teardown stops here, and everything this resource depends on survives. |
| `after_destroy` | **Confirmation** that the delete's effects actually happened. | Teardown stops before this resource's own dependencies are destroyed. |

`on_failure` applies as Terraform defines it:
- **`halt`** (default): the run fails.
- **`taint`** (`after_create` only): the object is tainted, so the next plan replaces it.
- **`continue`:** a warning, and dependents proceed.

**Engine requirement (new).** A destroy-event invocation must reach the cluster
through the provider configuration evaluated against **prior state**. This is
the same rule graceful teardown already applies to destroy RPCs. When the
cluster itself is being replaced, the planned configuration points at a cluster
that does not exist yet. Neither Turf engine applies that pin to action
invocations today.

Keep destroy-event configs to literals and variables: Terraform restricts what a
destroy-time action config may reference.

## Progress

The wait streams progress through `InvokeAction`'s `SendProgress`:
- on every verdict change;
- every `progress_interval` otherwise;
- carrying the observed object(s), the pending/success/failure verdict and the reason, the elapsed and remaining budget, and each of `progress_fields`.

What a Turf plan could show (illustrative, not measured):

```
  invoke  module.certification.action.kubewait_condition.gpu_census              before_create
  create  module.certification.kubernetes_manifest.certification
  invoke  module.certification.action.kubewait_condition.certification_terminal  after_create (on_failure = taint)
  create  module.cuj_train[0].kubernetes_manifest.trainjob
  invoke  module.cuj_train[0].action.kubewait_condition.trainjob_finished       after_create (on_failure = taint)

progress certification_terminal: nvcre-certification/gpu-pools InProgress/WorkflowRunning 12m/60m
         categoryStatuses: communication/nccl-all-reduce=InProgress
```

## The five uses in this example

| # | Action | Attached to | Event | On failure | Replaces in AICR UAT |
| --- | --- | --- | --- | --- | --- |
| 1 | `gpu_census` | Certification | `before_create` | halt | `gpu_census_verdict` (`tests/uat/lib/phases.sh`) |
| 2 | `certification_terminal` | Certification | `after_create` | taint | draft PR #2519's `waitForCRETerminal` |
| 3 | `trainjobs_drained`, `pods_drained` | Certification | `after_destroy` | halt | ADR-025 decision 6: confirm children are gone |
| 4 | `trainjob_finished` | TrainJob | `after_create` | taint | `phase_train`'s 15-second poll |
| 5 | `no_load_balancer_services` | `terraform_data.cluster_contents` | `before_destroy` | halt | `uat-aws-cleanup-lb.sh graceful` (#1617) |

Two of them in full (`modules/certification/main.tf`):

```hcl
# 1. Exactly the expected nodes, all Ready, none cordoned or still carrying
#    nodewright's runtime-required taint, each advertising its GPUs, and
#    the same set the plan named in target.nodeNames.
action "kubewait_condition" "gpu_census" {
  config {
    api_version        = "v1"
    kind               = "Node"
    label_selector     = "nodeGroup=gpu-worker"
    min_matching       = var.expected_nodes
    max_matching       = var.expected_nodes
    require_all        = true
    success_conditions = [{ type = "Ready", status = "True" }]
    expression         = <<-CEL
      !(has(object.spec.unschedulable) && object.spec.unschedulable) &&
      !(has(object.spec.taints) && object.spec.taints.exists(t, t.effect == "NoSchedule" &&
          (t.key.startsWith("nodewright.nvidia.com") || t.key.startsWith("skyhook.nvidia.com")))) &&
      has(object.status.allocatable) && "nvidia.com/gpu" in object.status.allocatable &&
      int(object.status.allocatable["nvidia.com/gpu"]) >= 8
    CEL
    set_expression     = "objects.all(o, o.metadata.name in [\"ip-10-0-130-4.ec2.internal\", …])"
    timeout            = "30m"
    settle             = "20s"
  }
}

# 2. NVCRE has no status.phase: a Certification is terminal when Succeeded or
#    Failed is True. settle covers the one non-monotonic case: with
#    repeatCount > 1 the controller can move Failed back to InProgress.
action "kubewait_condition" "certification_terminal" {
  config {
    api_version        = "nvcre.nvidia.com/v1alpha1"
    kind               = "Certification"
    namespace          = "nvcre-certification"
    name               = "gpu-pools"
    success_conditions = [{ type = "Succeeded", status = "True" }]
    failure_conditions = [{ type = "Failed", status = "True" }]
    absent             = "failure"
    timeout            = "60m"
    settle             = "2m"
    progress_fields    = ["status.conditions", "status.categoryStatuses"]
  }
}
```

The drain in use 5 has a limit worth stating. By the time it runs, the graph has
already deleted every Service it created (helm uninstall). The drain can only
see Services something *else* created, for example a test workload. It fails
closed and names them. It does not delete them, so the leak in AICR #1617
becomes a halted teardown with a list, not a fixed one.

## What it is not

- **Not a reconciler.** It observes; it never converges anything.
- **Not a readiness framework.** `helm_release.wait` and AICR's readiness-hook
  Jobs keep their jobs. This is for the edges those do not cover: custom-resource
  status, sets of objects, and teardown.
- **Not specific to NVCRE.** Only uses 2 and 3 know about it.
