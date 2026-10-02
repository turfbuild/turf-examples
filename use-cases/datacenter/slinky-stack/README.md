# Slurm in a Run:ai project, with the Run:ai part open-sourced

NVIDIA's Run:ai documentation has a tutorial,
[Deploying Slurm](https://run-ai-docs.nvidia.com/saas/tutorials/training-tutorials/deploying-slurm),
that runs a whole Slurm cluster inside a Run:ai project using
[Slinky](https://slinky.schedmd.com/), SchedMD's Slurm operator for Kubernetes.
(NVIDIA acquired SchedMD in December 2025, so this is now NVIDIA's own Slurm
stack.) Run:ai schedules every Slurm pod against the project's GPU quota, and
Slurm schedules the jobs inside them.

This example is that tutorial as one configuration, on a `kind` cluster with
**no GPU and no credentials**. The one proprietary piece, the Run:ai control
plane, is replaced by [KAI Scheduler](https://github.com/kai-scheduler/KAI-Scheduler),
the scheduler inside Run:ai that NVIDIA open-sourced.

```bash
turf-driver up -converge -auto-approve use-cases/datacenter/slinky-stack
```

Two rounds, 12 to 15 minutes from nothing on a cold image cache, and at the end
a Slurm cluster that answers `srun`:

```
$ sinfo -o "%20N %10P %8T %5c %8m %25G"
NODELIST             PARTITION  STATE    CPUS  MEMORY   GRES
slinky-[0-1]         all*       idle     12    24784    (null)
$ srun -N2 hostname
slinky-0
slinky-1
```

## In plain terms

The tutorial is eight steps across three tools: `helm install` three times,
`kubectl create configmap` and `kubectl patch` for the GPU settings, and the
`runai` CLI to submit a GPU worker pool into the project. Each step assumes the
one before it has *finished*, not just returned, and nothing records which steps
have run.

Here the same cluster is one dependency graph:

```
kind_cluster.dc
  ├─ cert_manager ─────────────► slurm_operator ──┐  depends_on: CRDs served, webhook up,
  │                                               │  the operator outlives what it finalizes
  ├─ gpu_operator ── dcgm_job_mapping_dir ────────┤
  └─ kai_scheduler ── scheduler_name, queue ──────┴─► slurm
       [after_create: KAI ready]                       [after_create: CPU partition up]
                                                       [after_destroy: Slurm pods drained]
```

Square brackets are **waits**: `kubewait_condition` actions from
[`turfbuild/kubewait`](https://github.com/turfbuild/terraform-provider-kubewait),
attached to the lifecycle event they guard. They are where "it returned" becomes
"it finished".

## The tutorial, step by step

| Tutorial step | Here |
| --- | --- |
| 1. Run:ai login / access key | nothing: no Run:ai |
| 2. `helm install cert-manager` | `modules/cert-manager` |
| 3. `helm install slurm-operator-crds`, `slurm-operator` | `modules/slurm-operator`, two releases, the CRDs first |
| 4. `helm install slurm --set-json 'nodesets={"slinky":{}}' …` | `modules/slurm`, values built from typed variables |
| 5. `runai workload list --project slurm` | `kubectl -n slurm get podgroups` |
| 6. `runai workload submit --file nodeset-gpu.yaml` | `nodesets.gpu` in the same release (`var.gpu_nodeset`) |
| 7. `kubectl create configmap slurm-gres-conf` + `kubectl patch controller slurm` | `configFiles."gres.conf"` and `controller.extraConfMap.GresTypes` in the same release |
| 8. `sinfo`, `srun --gres=gpu:1` | [Verify](#verify) |

Step 7 deserves a word. The tutorial patches the `Controller` custom resource
that the `slurm` Helm release owns: the GPU settings live in the cluster and in
no file, and the next `helm upgrade` renders that object again from values that
never heard of them. The chart has had keys for both all along (`configFiles` is
a map of extra files for `/etc/slurm`), so here they are values. The NodeSet
from step 6 is a values entry too, rather than an object submitted beside the
release.

## Run:ai, open-sourced

KAI Scheduler is the scheduling engine of Run:ai. It does not have Run:ai's
control plane, so a few things the tutorial gets for free are written out:

| Run:ai | KAI, here |
| --- | --- |
| a department | `Queue` `datacenter`, the parent (`modules/kai-scheduler/queues/`) |
| project `slurm` and its GPU quota | `Queue` `slurm`, a leaf, `resources.gpu.quota = var.queue_gpu_quota` |
| the project takes over the namespace's scheduling | each Slurm pod sets `schedulerName: kai-scheduler` and the label `kai.scheduler/queue: slurm`, through the chart's `podSpec` and `metadata` values; KAI has no namespace-level injection |
| "NodeSet is a natively supported workload type" | a `ClusterRole` letting KAI's pod-grouper read `slinky.slurm.net` `nodesets` |
| NodeSet default: very high priority, non-preemptible | Slinky's own `slurm-system-critical` PriorityClass (`priorityClass.enabled`) |

The pod-grouper line is the interesting one. KAI makes one PodGroup per *top
owner*, found by walking `ownerReferences`. A slurmd pod is owned directly by its
NodeSet, but stock KAI may not read NodeSets, so its walk stops at the pod: one
PodGroup per Slurm node. With read access granted, the measured result is one per
NodeSet, the same shape as the tutorial's `runai workload list`:

```
$ kubectl -n slurm get podgroups
pg-slurm-controller-…         # StatefulSet slurm-controller
pg-slurm-login-slinky-…       # Deployment slurm-login-slinky
pg-slurm-restapi-…            # Deployment slurm-restapi
pg-slurm-worker-gpu-…         # NodeSet slurm-worker-gpu, minMember 1
pg-slurm-worker-slinky-…      # NodeSet slurm-worker-slinky — both slurmd pods
```

Set `use_kai_scheduler = false` and the KAI module drops out: every Slurm pod
goes to the default scheduler, which is the tutorial with Run:ai taken out. On a
real Run:ai cluster that is also the setting to use, and the project's own
enforcement does the rest.

## The seam: a GPU partition with no GPUs

The GPU NodeSet asks for 4 × `nvidia.com/gpu` per slurmd pod, as the tutorial's
does. The GPU Operator is installed and healthy, finds no NVIDIA PCI device,
and deploys no device plugin, so no node ever advertises the resource. The pod
pends, and KAI says exactly why:

```
$ kubectl -n slurm get pod slurm-worker-gpu-0 -o jsonpath='{.status.conditions[0].message}'
Scheduling conditions were not met for pod slurm/slurm-worker-gpu-0:
MaxNodePoolResources: The pod slurm/slurm-worker-gpu-0 requires GPU: 4, CPU: 0 (cores),
memory: 0 (GB), pods: 1. No node in the default node-pool has GPU resources.
```

Slurm never hears of the node: a slurmd that never starts never registers. So
the tutorial's "expected rejection on a non-GPU node" is, on this cluster, the
answer from every node:

```
$ srun --gres=gpu:1 hostname
srun: error: Unable to allocate resources: Requested node configuration is not available
```

Everything up to that line is what a GPU cluster runs: the GRES configuration
(`GresTypes = gpu`, `AutoDetect=nvidia`), the GPU partition, the queue, the
DCGM job-mapping directory. Everything after it needs silicon.

`gpu_nodes_up` is the same question asked of Slurm, as a wait triggered by
nothing. Invoke it when you want to know:

```
$ turf-driver invoke -auto-approve use-cases/datacenter/slinky-stack \
    module.slurm.action.kubewait_condition.gpu_nodes_up
...
kubewait_condition timed out: No verdict on slinky.slurm.net/v1beta1 NodeSet settled within timeout (1m).
pending: slurm/slurm-worker-gpu: expression false · 1m elapsed, 0s left
  slurm/slurm-worker-gpu status.replicas=1 status.unavailableReplicas=1 status.slurmIdle=<none>
```

On a cluster with GPUs it passes as soon as the GPU nodes register. A failed
invoke leaves its phase holding the workspace, by design; `turf-driver cancel
use-cases/datacenter/slinky-stack` releases it.

## The waits

Helm's `wait = true` waits for the Deployments and StatefulSets in a release's
manifest to be ready. Two of this stack's releases have nothing it can wait for.

**KAI is operator-shaped.** The chart installs `kai-operator` and a `Config`;
the operator then deploys the scheduler, binder, pod-grouper, admission webhook
and queue controller. The queue controller serves a validating webhook for
`Queue` objects that fails closed. With helm's wait alone, this happened
(measured):

```
effect module.kai_scheduler[0].helm_release.queues:create failed: apply errors: Helm release error:
  * Internal error occurred: failed calling webhook "queue-validation.kai.scheduler": failed to call
    webhook: Post "https://queue-controller.kai-scheduler.svc:443/validate-scheduling-run-ai-v2-queue?timeout=10s":
    dial tcp 10.96.19.182:443: connect: connection refused
```

The Queue was refused at 17:40:36; the operator reported KAI `Ready=True` 53
seconds later. So the KAI release carries a hook on the operator's own verdict:

```hcl
action "kubewait_condition" "kai_ready" {
  config {
    api_version        = "kai.scheduler/v1"
    kind               = "Config"
    name               = "kai-config"
    success_conditions = [{ type = "Ready", status = "True" }]
    timeout            = "10m"
  }
}
```

```
invoke    module.kai_scheduler[0].action.kubewait_condition.kai_ready  (after_create …): invoked
    > pending: kai-config: Ready=False (not_ready) · 0s elapsed, 10m left
    > success: kai-config: Ready=True · 52s elapsed, 9m8s left
```

**The `slurm` release renders no workloads at all**: only a `Controller`, a
`RestApi`, a `LoginSet`, two `NodeSet`s and their Secrets and ConfigMaps. The
operator makes the pods. So the release sets `wait = false`, and the wait that
means something is a hook on what Slurm itself reports. The NodeSet's status
carries the operator's count of its pods by Slurm state (IDLE, ALLOCATED, DOWN,
DRAIN), and pods being Ready is not the same thing — a slurmd can run and still
be DOWN to the controller:

```hcl
action "kubewait_condition" "cpu_nodes_up" {
  config {
    api_version = "slinky.slurm.net/v1beta1"
    kind        = "NodeSet"
    namespace   = var.namespace
    name        = "${var.release_name}-worker-slinky"
    expression  = <<-CEL
      has(object.status) && has(object.status.readyReplicas) &&
      object.status.readyReplicas == ${var.cpu_nodeset_replicas} &&
      (has(object.status.slurmIdle) ? object.status.slurmIdle : 0) +
      (has(object.status.slurmAllocated) ? object.status.slurmAllocated : 0) == ${var.cpu_nodeset_replicas} &&
      !(has(object.status.slurmDown) && object.status.slurmDown > 0)
    CEL
    timeout = var.ready_timeout
    settle  = "10s"
  }
}
```

It runs `after_create` with `on_failure = taint` (a cluster that never came up
is reinstalled by the next `up` rather than left in state looking finished), and
`after_update` without.

```
invoke    module.slurm.action.kubewait_condition.cpu_nodes_up  (after_create of module.slurm.helm_release.this): invoked
    > pending: slurm/slurm-worker-slinky: expression false · 0s elapsed, 15m left
slurm/slurm-worker-slinky status.readyReplicas=<none> status.slurmIdle=<none> status.slurmAllocated=<none> status.slurmDown=<none>
    ...
    > pending: slurm/slurm-worker-slinky: expression false · 4m elapsed, 11m left
slurm/slurm-worker-slinky status.readyReplicas=1 status.slurmIdle=1 status.slurmAllocated=<none> status.slurmDown=<none>
    > success: slurm/slurm-worker-slinky: expression true · 4m43s elapsed, 10m17s left · success held 0s of 10s
    > success: slurm/slurm-worker-slinky: expression true · 4m53s elapsed, 10m7s left · success held 10s of 10s
slurm/slurm-worker-slinky status.readyReplicas=2 status.slurmIdle=2 status.slurmAllocated=<none> status.slurmDown=<none>
```

Nearly five minutes, and the wait is not what is slow: it watches, and it passed
as soon as Slurm reported both nodes IDLE. What it was waiting for, from the
cluster's events in that run:

| From → to | Took | What |
| --- | --- | --- |
| `slurm` release deployed → slurmctld running | 1m35s | the controller pod's images pulled (alpine sidecar 40s, slurmctld 28s) |
| slurmctld running → slurmd pods created | 36s | Slinky's NodeSet controller in backoff (below) |
| slurmd pods created → both started | 1m51s | the slurmd image pulled on each kind node, in parallel: 62s and 98s |
| both started → both IDLE, plus the 10s settle | about 40s | slurmd registers with slurmctld; the operator updates the NodeSet |

About three and a half of those minutes are image pulls onto fresh kind nodes,
which share no image store. The backoff is Slinky's: the chart creates the
NodeSets alongside the Controller, every NodeSet reconcile fails with *"Unable to
contact slurm controller"* until slurmctld answers, and controller-runtime backs
off between tries. It cost 36 seconds here and two minutes in an earlier run.

**Teardown** runs the third wait. `helm uninstall` deletes the custom resources
and returns at once; it is the operator that then removes the pods. The slurm
release's `after_destroy` drain holds its destroy until the namespace has no
pods, and the operator's module depends on this one, so the operator outlives
everything it has to clean up (measured, `turf-driver down`):

```
  invoke    module.slurm.action.kubewait_condition.slurm_pods_drained  (after_destroy of module.slurm.helm_release.this): invoked
      > pending: 5 still match: slurm/slurm-controller-0; slurm/slurm-login-slinky-…; slurm/slurm-restapi-…;
                 slurm/slurm-worker-slinky-0; slurm/slurm-worker-slinky-1 · 2s elapsed, 4m58s left
      > success: no objects match · 31s elapsed, 4m29s left
```

Sampling `helm ls` meanwhile showed the order: `slurm` gone, then about half a
minute with every other release still installed, then `kai-scheduler-queues` and
`slurm-operator`, then the CRDs, cert-manager, the GPU Operator, KAI, the
cluster.

## What it does when you run it

Measured from empty on Turf (`turf-engine` `e71ee93`, `turf-driver up
-converge`), kind on Docker Desktop, 2026-10-01.

**Round 1** creates the cluster and the containment anchors. Every release defers,
because the `helm` provider is configured from the cluster's computed endpoint;
`slurm_operator` and `slurm` defer whole, on `depends_on` alone:

```
plan for phase p-8c08a794 (15 of 15 address(es) change):
  create    kind_cluster.dc
  create    module.cert_manager.terraform_data.cluster
  unspecified module.cert_manager.helm_release.this  (deferred)
  ...
  unspecified module.slurm_operator  (module deferred: absent_prereq)
  unspecified module.slurm  (module deferred: absent_prereq)
```

**Round 2** plans the remaining nine creates and both hooks at once (`no_op`
rows left out):

```
plan for phase p-113c7640 (9 of 13 address(es) change):
  actions: 2 invocation(s) planned, 0 deferred
  create    module.cert_manager.helm_release.this
  create    module.gpu_operator.helm_release.this
  create    module.kai_scheduler[0].helm_release.this
    invoke    module.kai_scheduler[0].action.kubewait_condition.kai_ready  (after_create, on_failure = taint)
  create    module.kai_scheduler[0].helm_release.queues
  create    module.slurm_operator.terraform_data.cluster
  create    module.slurm_operator.helm_release.crds
  create    module.slurm_operator.helm_release.operator
  create    module.slurm.terraform_data.cluster
  create    module.slurm.helm_release.this
    invoke    module.slurm.action.kubewait_condition.cpu_nodes_up  (after_create, on_failure = taint)
phase p-113c7640: applied (applied 9, failed 0, cancelled 0, invoked 2)
```

One command, from empty:

```
round 1 stages: reconcile 563ms | plan 16.145s | approve 0s | apply 2m22.154s | drain 996ms  | total 2m39.706s
round 2 stages: reconcile 813ms | plan 36.919s | approve 0s | apply 11m9.818s | drain 7.328s | total 11m49.059s
converged in 2 round(s)
```

That run took 14m32s; a later one's second round took 9m30s against 11m49s
here, the difference being image pulls and the NodeSet backoff (the
[timeline](#the-waits) is from the later run). A second `up` plans `0 of 13
address(es) change`, invokes nothing, and takes 49 seconds.

## The second run

Change something a Run:ai administrator would: the project's GPU quota.

```bash
turf-driver up -converge -auto-approve -var queue_gpu_quota=2 use-cases/datacenter/slinky-stack
```

```
plan for phase p-f32b7ea0 (1 of 13 address(es) change):
  update    module.kai_scheduler[0].helm_release.queues
phase p-f32b7ea0: applied (applied 1, failed 0, cancelled 0, invoked 0)
round 1 stages: reconcile 869ms | plan 39.88s | approve 0s | apply 4.96s | drain 975ms | total 46.614s
```

One release updated in place, the `Queue` with it (`gpu quota=2`), nothing else
touched, no hook run (`kai_ready` is `after_create` only). What KAI says about the
GPU pod does not change: it still reports that no node in the pool has GPUs. With
no GPU node at all, the node-pool check comes before the queue's quota, so a
quota is only visible on a cluster with GPUs to be over it.

## The modules

Each wraps one concern in a single `main.tf`: `required_providers`, variables, a
`terraform_data` containment anchor, the release(s), outputs.

| Module | Chart(s) | Pin | Why it is here |
| --- | --- | --- | --- |
| `modules/cert-manager` | `jetstack/cert-manager` | `v1.21.2` | the Slurm operator's webhook certificate (`certManager.enabled` is the chart default) |
| `modules/slurm-operator` | `slinkyproject/slurm-operator-crds`, `slurm-operator` | `1.2.2` | six CRDs (`Controller`, `NodeSet`, `LoginSet`, `RestApi`, `Accounting`, `Token`) and the operator; its validating webhook fails closed, so `wait = true` here does matter |
| `modules/gpu-operator` | `nvidia/gpu-operator` | `v26.7.0` | device plugin and DCGM exporter on GPU nodes; on kind, none — and HPC job mapping turned on for DCGM |
| `modules/kai-scheduler` | `kai-scheduler/kai-scheduler` + local `queues/` | `v0.18.1` | the scheduler, the department and project queues, and the pod-grouper's read access to NodeSets |
| `modules/slurm` | `slinkyproject/slurm` | `1.2.2` | the Slurm cluster: controller, REST API, login node, CPU and GPU NodeSets, one partition |

Three edges into `module.slurm`, three kinds:
- **`scheduler`**, a value from KAI. The `queue` output is read back from the
  values the queues release was installed with, so binding it orders the Slurm
  release after the queue exists.
- **`dcgm_job_mapping_dir`**, a value from the GPU Operator. Slurm's prolog
  writes which job holds which GPU into a host directory that DCGM exporter
  reads. The two vendors' charts default to the same path by convention; here
  one is bound to the other's output.
- **`depends_on = [module.slurm_operator]`**, order only, and needed three ways:
  the CRDs must be served, the webhook must be up, and on the way down the
  operator must outlive the objects it finalizes.

## Prerequisites

- Docker, `kind` and `kubectl`. If you run more than one container engine, pin
  the one you mean (`export DOCKER_CONTEXT=…`); kind builds into whichever is
  current.
- **Turf**: `turf-engine` and `turf-driver`, and a `restate-server` (`make
  restate-dev` in the engine's checkout).
- **`turfbuild/kubewait` 0.1**, which is on no registry yet. Build it and lay it
  out where the engine looks:

  ```bash
  make -C ../terraform-provider-kubewait mirror     # → .mirror/registry.terraform.io/…
  mkdir -p ~/.cache/turf-mirror/registry.opentofu.org/turfbuild
  cp -R ../terraform-provider-kubewait/.mirror/registry.terraform.io/turfbuild/kubewait \
        ~/.cache/turf-mirror/registry.opentofu.org/turfbuild/
  TF_PROVIDER_MIRROR_DIR=~/.cache/turf-mirror bin/turf-engine    # in the engine's checkout
  ```

  The engine resolves an unqualified `turfbuild/kubewait` against
  registry.opentofu.org, so the mirror entry goes under that hostname.
- No NGC account, no Run:ai tenant, no cloud credentials. About 3.5 GB of
  images across the three kind nodes.

## Usage

```bash
turf-driver up -converge -auto-approve use-cases/datacenter/slinky-stack
```

## Verify

```bash
export KUBECONFIG=$PWD/use-cases/datacenter/slinky-stack/slinky-1-config
x() { kubectl -n slurm exec deploy/slurm-login-slinky -- "$@"; }

x sinfo -o "%20N %10P %8T %5c %8m %25G"     # slinky-[0-1] idle; no gpu-0
x srun -N2 hostname                          # slinky-0, slinky-1
x srun --gres=gpu:1 hostname                 # Requested node configuration is not available
x scontrol show config | grep GresTypes      # GresTypes = gpu

kubectl -n slurm get nodesets                # READY 2 for slinky; nothing for gpu
kubectl -n slurm get podgroups               # one per workload, NodeSets included
kubectl -n slurm get pod slurm-worker-gpu-0 \
  -o jsonpath='{.spec.schedulerName} {.metadata.labels.kai\.scheduler/queue}{"\n"}'
kubectl get queues                           # datacenter → slurm, gpu quota 4
```

For an SSH session like the tutorial's, set `root_ssh_authorized_keys` and
port-forward the login Service (`ClusterIP` here: the chart's default
`LoadBalancer` never gets an address on kind):

```bash
kubectl -n slurm port-forward svc/slurm-login-slinky 2222:22 &
ssh -p 2222 root@127.0.0.1
```

## Cleanup

```bash
turf-driver down -auto-approve use-cases/datacenter/slinky-stack
```

## Pointing this at real GPUs, or a real Run:ai

- **GPUs.** Point the `helm` and `kubewait` providers at the cluster instead of
  `kind_cluster.dc`. On node pools whose image ships no driver or runtime
  configuration, set `gpu_driver_enabled` and `gpu_toolkit_enabled`. Size
  `gpu_nodeset` to the nodes and `queue_gpu_quota` to `gpu_nodeset`. The GPU
  NodeSet pods schedule, slurmd registers with `AutoDetect=nvidia`, and
  `gpu_nodes_up` passes.
- **Run:ai.** Set `use_kai_scheduler = false` and install into the project's
  namespace; Run:ai takes the pods from there.

## Outside this example

- **Accounting.** `slurmdbd` needs an external MariaDB (the chart has no
  subchart for it), so `sacct` and `sacctmgr` do not work here. The chart's
  `accounting` block points at one.
- **Autoscaling** NodeSets with KEDA on Slurm's own pending-job metrics, the
  chart's `topology.yaml` support, pyxis/enroot, and IMEX through the NVIDIA DRA
  driver.
- **Gang scheduling.** KAI's default grouper gives each NodeSet `minMember 1`.
  A Karta (KAI's workload description, now Workload-Map) for NodeSet would make
  it all-or-nothing.

## Notes, measured

Everything below was observed on `turf-engine` `e71ee93` with `turf-driver`,
kind `v1.36.1` on Docker Desktop, on 2026-10-01.

- **No `depends_on` on a module output.** The first version ordered
  `dcgm_job_mapping_dir` and the KAI `queue` output after their releases with
  `depends_on`. The engine refuses that outright, before planning anything:
  *"this engine milestone does not walk depends_on on outputs (found:
  [dcgm_job_mapping_dir]); the construct is refused rather than skipped"*. Both
  outputs now read their value back from the release itself
  (`helm_release.this.set`, `helm_release.queues.values`), which carries the
  ordering as a real reference.
- **A failed install leaves helm's record behind, and no state.** When the
  queues release was refused by KAI's webhook, helm had already written the
  release, so the cluster held `kai-scheduler-queues` with status `failed` and
  the statefile held nothing for it. That is `hashicorp/helm` 3.x, not the
  engine: Terraform 1.16.2 leaves exactly the same pair (an empty state, a
  `failed` release) for an install whose `wait` times out, and the provider says
  so — *"Helm release … was created but has a failed status … run Terraform
  again."* The next install of the same name meets the leftover; `helm
  uninstall` it, or replace the cluster.
- **A failed phase holds the workspace.** A create that fails, an invoke that
  times out, or a plan staled by an edit leaves its phase open (*"one phase at a
  time — drive it to a verdict, or `turf-driver cancel` it"*). Terraform just
  exits; here, `turf-driver cancel use-cases/datacenter/slinky-stack` releases
  it. Editing a `.tf` under the directory while a round is planning stales that
  round's plan (*"plan is stale: the configuration changed after it was
  planned"*): nothing applies, and the next `up` re-plans.
- **The CPU wait's first minutes are the cluster, not the wait.** See
  [What it does when you run it](#what-it-does-when-you-run-it). Slinky's NodeSet
  controller is created alongside the Controller, fails every reconcile until
  slurmctld answers, and backs off; the slurmd images are pulled per kind node.
- **KAI checks the node pool before the queue.** With `queue_gpu_quota = 2`, half
  of what the GPU NodeSet asks for, KAI's verdict on the GPU pod is unchanged:
  *"No node in the default node-pool has GPU resources"*. A quota is only
  visible where there are GPUs to be over it.
- **`kind_cluster` refreshes with a note, once.** Round 2 reports
  `kind_cluster.dc (drifted outside turf; state absorbs the refreshed values on
  apply)`: the provider reads `feature_gates`, `labels` and `runtime_config` back
  as empty maps where the configuration has none. It plans `no_op`, round 2's
  apply absorbs the values, and later plans show a plain `no_op`.
- **One slurmd per Kubernetes node.** The operator gives every slurmd pod a
  required anti-affinity against every other, across NodeSets, so
  `cpu_nodeset_replicas` is capped by `worker_count`. `oversubscribeNode` lifts
  it, and the chart warns against it for production.
