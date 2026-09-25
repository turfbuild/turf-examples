# `kubewait_condition`: a Terraform action that waits on Kubernetes state

**Status: implemented, not on a registry yet.**
[`turfbuild/kubewait`](https://github.com/turfbuild/terraform-provider-kubewait)
0.1.0 implements this spec, and this example uses it (installed locally; see
README.md §Validating and testing). Its waits are tested against a real API server
(envtest, Kubernetes 1.37), with the NVCRE v0.2.0 Certification and Kubeflow
Trainer v2.2.0 TrainJob CRDs, and under Terraform 1.16.2. None of the five
waits here has run against this example's cluster. Where this spec left a
choice open, [Implementation decisions](#implementation-decisions) records what
the provider does.

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

`turfbuild/kubewait`. The provider configuration is the kubernetes provider's
connection schema: `host`, `cluster_ca_certificate`, `exec {}`, `config_path`,
`config_context`, and so on, with the same `KUBE_*` environment variables.
`providers.tf` configures it the way it configures the kubernetes provider.

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

**The Terraform CLI does not honour these gates at full teardown (measured,
1.16.2).** In a `terraform destroy` walk, Terraform turns a failed destroy-event
action into a warning whatever `on_failure` says ("a full destroy walk must
never be blocked"), and the delete proceeds. A failed `before_destroy` gate
halts only a destroy inside an ordinary apply, such as a replace. The table
above is what an engine has to provide for uses 3 and 5 to hold at teardown.

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

## Implementation decisions

Where this spec left a choice open, `turfbuild/kubewait` 0.1.0 decides as
follows. "Measured" means observed in the provider's tests or under Terraform
1.16.2.

**Evaluation**
- **CEL runtime errors pin the verdict at pending.** An error, such as a missing
  field without a `has()` guard, never counts as success or failure by itself.
  Progress names it. A failure proven on another object still wins. A
  persistent error ends in the timeout failure, which names the error. This
  fails closed: a `filter` error cannot let a drain pass with objects still
  present.
- **CEL is type-checked when the config is validated, and evaluated
  dynamically.** `object` is a `map(string, dyn)`. cel-go's checker narrows an
  index on `dyn` to the type of whatever consumes it, so
  `int(object.status.allocatable["nvidia.com/gpu"])`, as in the census, would
  fail at runtime with "no such overload" (measured on cel-go 0.29.2, 0.31.0
  and 0.32.0). Evaluating the unchecked program avoids that. The ext
  `strings`, `lists`, `sets` and `encoders` libraries are available, and each
  evaluation has a cost limit.
- **A drain needs `min_matching = 0`.** `max_matching = 0` with the default
  `min_matching` of 1 is rejected as `min_matching > max_matching`, with a hint.
- **Attributes that do nothing in the chosen mode are warnings, not errors.**
  This covers `filter`, `set_expression`, `min_matching`, `max_matching` and
  `require_all` in single-object mode, and `absent` in set mode.

**Watching**
- **An API error resets settle.** A retried error counts as a pending
  observation, because an interval nobody observed cannot count toward "held
  continuously". Without the reset, an NVCRE Failed → InProgress → Failed flip
  during an outage could settle as a false failure. Retries back off from 1s up
  to `poll_interval`.
- **401 gets one immediate retry before failing.** client-go's exec plugin (here
  `aws eks get-token`) fetches a new token only on the request after a 401.
  Without the retry, a token that expired partway through a 60-minute wait would
  end the wait. This was measured: without the retry, an exec plugin that
  returns an expired token and then a valid one fails the wait; with it, the
  wait succeeds. 403 fails at once.
- **A kind the server does not serve counts as no objects.** A 404 for the
  group/version, or a group/version that lacks the kind, is observed as the
  empty set:
  - drains pass;
  - set-mode success waits stay pending;
  - single-object mode applies `absent`.

  The kind is discovered again on every resync, so a CRD established mid-wait
  is picked up. Every progress event says `kind … not served (treated as no
  objects)`, and a success reached this way carries a warning naming the kind,
  in case it is misspelled. Any other discovery error, such as the 503 of an
  unavailable aggregated API, is retried, never treated as "not served".
- **Resync replaces the watch.** Every `poll_interval` the wait stops the watch,
  re-lists and watches again from the new list. A stopped watch's late events
  never reach the fresh snapshot. A watch that closes, or answers 410 Gone,
  starts a new cycle; it is not an error.

**Connection**
- **No localhost, and no implicit namespace.** With nothing configured, a wait
  uses in-cluster credentials when it runs in a pod, as the kubernetes provider
  does, and otherwise fails. A provider configuration that was unknown when the
  provider was configured is always an error. From a pod, an empty
  configuration observes the pod's own cluster, where a drain of a kind or
  namespace that cluster lacks passes, so configure destroy-event drains
  explicitly. Once discovery tells it the kind's scope, the wait also fails at
  once on:
  - `namespace` set on a cluster-scoped kind;
  - single-object mode on a namespaced kind without `namespace`.

**Progress**
- **When progress goes out:**
  - when the verdict changes;
  - on entering or leaving an API-error or unserved state;
  - every `progress_interval` otherwise;
  - once at the end.

  Line 1 carries the verdict, the reason, the elapsed and remaining budget, and
  how long an unsettled verdict has held. One line per observed object follows,
  capped at 10, with each of `progress_fields`. Condition lists render as
  `Type=Status(Reason)`.
- **Terraform 1.16.2 prints each progress event verbatim, multi-line included**
  (measured):

  ```
  Action action.kubewait_condition.terminal (triggered by terraform_data.cert): pending: nvcre-certification/gpu-pools: Succeeded=False (WorkflowRunning) · 3s elapsed, 57s left
    nvcre-certification/gpu-pools status.conditions=[Succeeded=False(WorkflowRunning) Failed=False(WorkflowRunning)] status.categoryStatuses=[{"domain":"communication","status":"InProgress","variant":"nccl-all-reduce"}]
  ```

**When validation runs**
- **Under Terraform 1.16.2 (measured):**
  - `terraform validate` calls `ValidateActionConfig`. Values from variables
    and data sources are unknown there, and checks that need them are skipped.
  - `terraform plan` calls `PlanAction`, which repeats the checks with the
    values known. A violation that arrives through a variable fails there.
- **Invoke validates again.** The MCP engine implements only `InvokeAction`,
  not `ValidateActionConfig` or `PlanAction`. Under it, a bad wait config
  therefore fails when the action is invoked, not at plan.
- **No plan-time deferral yet.** `PlanAction` never contacts the cluster and
  never defers. The intended shape, once an engine calls `PlanAction` with
  `DeferralAllowed`:
  - if the connection is known and discovery says the kind is not served
    (its CRD arrives in the same apply), return `Deferred{AbsentPrereq}`;
  - the engine must defer the trigger along with the action. Otherwise an
    `after_create` hook's dependents would start before the wait has run.

## What it is not

- **Not a reconciler.** It observes; it never converges anything.
- **Not a readiness framework.** `helm_release.wait` and AICR's readiness-hook
  Jobs keep their jobs. This is for the edges those do not cover: custom-resource
  status, sets of objects, and teardown.
- **Not specific to NVCRE.** Only uses 2 and 3 know about it.
