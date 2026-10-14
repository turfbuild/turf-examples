# An AICR recipe, deployed as the graph it actually is

Almost nothing in this directory was written by hand. Everything under
`bundle/` was **generated** from a single [NVIDIA AI Cluster Runtime](https://github.com/NVIDIA/aicr)
(AICR) recipe by `aicr bundle --deployer terraform`, and that is the point of
the example.

AICR publishes validated, version-locked combinations of GPU drivers, operators
and system configuration as *recipes*, and renders them for Helm, Argo CD, Flux
or Helmfile. It is explicit that it is **not a cluster provisioner** — "you bring
your GPU-accelerated Kubernetes cluster and your deployment tooling." That
boundary is a hard edge in everything it emits: the cluster is a precondition,
never a node in the graph.

Terraform is the one consumer that can put the cluster *in* the graph. The two
hand-written files here — `main.tf` and `versions.tf`, about forty lines
together — create a kind cluster and hand it to the generated bundle. Seventeen
Helm releases — sixteen for the recipe's fourteen components, plus the GPU
Operator's readiness gate — come up behind it, from nothing, in one command.

```
turf -C use-cases/datacenter/aicr-stack up
```

Or from any MCP client; see [Running the examples](../../../README.md#running-the-examples).

## What the recipe actually says

The recipe resolved here is `service=kind, accelerator=h100, intent=inference`:
**14 components, 16 dependency edges, and a DAG four levels deep.**

```
level 0  agentgateway-crds  cert-manager  nfd  nodewright-operator  prometheus-operator-crds
level 1  agentgateway  kube-prometheus-stack  network-operator
level 2  gpu-operator  k8s-ephemeral-storage-metrics  prometheus-adapter
level 3  kai-scheduler  nvidia-dra-driver-gpu  nvsentinel
```

Each component carries a `dependencyRefs` list. The deployer turns that list —
and nothing else — into `depends_on` between module calls:

```hcl
module "gpu_operator" {
  source = "./modules/component"
  ...
  depends_on = [
    module.cert_manager,
    module.kube_prometheus_stack,
    module.nfd,
  ]
}
```

A recipe also ships a precomputed flat `deploymentOrder`. **The deployer ignores
it.** That field is a linearisation of the graph above, and handing a
linearisation to an engine built to schedule graphs throws away the only thing
worth carrying.

Which matters, because most of AICR's renderers cannot carry it. `helm` emits a
line of sixteen. `argocd` emits sync-waves 1/5/9/13 and `helmfile` emits nested
`level-0…3.yaml` — both of which are *barriers*, not edges. Only `flux` and this
deployer emit the real graph, and Flux is an in-cluster reconciler that cannot
create the cluster it reconciles into.

The 16 edges above are between *components*. A component that ships
pre-manifests, post-manifests or a readiness gate expands into several Helm
releases — 16 releases here for 14 components, 17 with the GPU Operator's
readiness gate — and those chain **inside** the component's module. So `depends_on = [module.agentgateway_crds]` covers that
component's post-manifest release too, without naming it.

The two that keep the graph agree on it exactly: rendering this recipe through
`--deployer flux` and `--deployer terraform` produces the same eighteen edges,
release for release.

### What a barrier costs

Measured, on one `helmfile sync` of this same recipe. helmfile reports a
per-release `DURATION`, so both scheduling models can be computed from a single
run's own numbers — there is no second run here, and so nothing to be noisy.

First the wave model is checked against the run that produced it: over these
durations it predicts **204s** against an observed **213s**, so 9s is helmfile
overhead. Then the same durations under the DAG the recipe declares:

```
makespan   DAG = 152s     waves = 204s     difference = 52s  (25%)
```

The clearest single case: **`kube-prometheus-stack` waits 58 seconds for
`nodewright-operator`** — a component with no edges into or out of it anywhere in
this recipe. It sits in level 0 and takes 64s, so under a barrier model every
level-1 component pays for it. Under the DAG nobody does.

(This assumes unlimited parallelism — as the observed wave run had *within* a
level — and that a release's duration does not change with scheduling. It is a
comparison of scheduling models over measured durations, not a measured race.
Reproduce the helmfile side with `--deployer helmfile` against `bundle/recipe.yaml`.)

## Everything here is credential-free

Seventeen releases, eight registries — `nvcr.io`, `cr.agentgateway.dev`,
`ghcr.io/nvidia/nodewright`, `ghcr.io/nvidia/nvsentinel`, `ghcr.io/kai-scheduler`,
`registry.k8s.io/dra-driver-nvidia`, `charts.jetstack.io`, the Prometheus
community charts and the gate's `ghcr.io/nvidia/aicr-gate` — and **no key, no
secret, no `imagePullSecrets`**. This was the
open question before the stack was first run, and the answer is that the whole
kind recipe pulls anonymously.

## And there is no GPU

Same story as [`../ngc-stack`](../ngc-stack/README.md), with more surface area.
On a kind node with no NVIDIA hardware:

```
ClusterPolicy: ready   reason=NoGPUNodes
no feature.node.kubernetes.io/pci-* labels on the node
```

The GPU Operator creates **no** operand DaemonSets at all. The two components
that are new here relative to the NGC stack both land cleanly rather than
crashlooping — they create DaemonSets that sit at zero:

```
nvidia-dra-driver  nvidia-dra-driver-gpu-kubelet-plugin  desired=0
nvsentinel         gpu-health-monitor-dcgm-{3,4}.x       desired=0
nvsentinel         metadata-collector                    desired=0
nvsentinel         syslog-health-monitor-{kata,regular}  desired=0
```

One Node Feature Discovery label is still the entire seam between this laptop and
a datacenter.

Note the recipe's kind overlay is written for **nvkind** — it sets
`driver.enabled: false` and `nvsentinel.labeler.assumeDriverInstalled: true`
because it assumes a driver installed on the host. On a plain kind cluster that
assumption is simply unmet, and the result is the clean idle above rather than an
error.

## What it does when you run it

Measured on Turf from empty state on 2026-10-13, through the MCP server (`init`,
`open`, `up`, `apply`), against the engine the server pins. The
containment shim is a `terraform_data`, a resource of the built-in
`terraform.io/builtin/terraform` provider that no registry serves; Turf runs that
provider as a sidecar process on the same path every other provider takes, so the
bundle runs exactly as generated.

Round one can plan and apply exactly six addresses — the cluster and the five
containment shims that sit behind no order-only edge. Everything else defers,
and nine of the fourteen components defer **whole**:

```
up:     round 1  planned 75   deferred 69   → awaiting_approval   add 6
apply:  round 1  applied 6
        round 2  planned 32   deferred 0    → awaiting_approval   add 26
                 invocations: action.turf_action.certify
                              after_create module.stack.module.gpu_operator.helm_release.this
apply:  round 2  … → awaiting_actions (certify)
apply:  round 2  applied 26   invoked 1   drift 1
converged in 2 round(s)
```

The `drift: 1` in round two is the kind provider reading back the kubeconfig
path it wrote after the create, not the bundle. The 26 of round two are the
seventeen releases and the nine shims that deferred with their modules.

`absent_prereq` is the engine saying a module is deferred because it depends —
transitively, over an edge that carries no value — on something else that is
deferred. Note that the DAG is four deep but converging costs **two** rounds, not
four: deferral is about unknown *values*, not graph depth. Once the cluster
exists the helm provider's configuration is known, the whole graph is plannable,
and ordering is then just the graph inside one apply.

`cert-manager` has no post-manifests and no readiness gate, yet its `post` and
`readiness` slots appear in that first plan. A slot is `count = 0` when the
bundle emitted no such folder, but a resource whose dependency is deferred is
deferred *before* its count is evaluated — and both slots depend on
`helm_release.this`. They collapse to zero instances in round two. And a module
that defers whole is still planned through, with every row inside it listed
beneath the call: that descent is what lets Turf find an object the round
*condemns* even when its forward plan has to wait, which the cluster replacement below
depends on. The cost is a noisier first plan: 75 rows for the 16 releases plus 14
shims plus the cluster that actually exist.

`turf -C use-cases/datacenter/aicr-stack destroy` removes all 32 addresses in a
single round.

### Replacing the cluster

This is what the containment shim is for, and the part the four engines in
[the host-replacement differential](https://github.com/turfbuild/turf-engine/blob/main/docs/development/designs/host-replacement-across-engines.md)
get wrong. The shim keys on `cluster_keepers`, the caller's statement of what
identifies the cluster; `main.tf` passes kind's endpoint, a port minted per
cluster, so it changes with every generation. `up --var generation=2` on the
converged stack replaces `kind_cluster.dc`. Every release's provider configuration now reads a cluster
that is being replaced, so no release can be planned forward — but every one of
them is *contained* by a shim that replaces this round, and Turf plans through the
deferred modules to find them:

```
up:     round 1  planned 75   deferred 69   → awaiting_approval
                 replace 6 (kind_cluster.dc + the 5 shims behind no edge)
                 destroy 23 (all 17 releases: replace_by_triggers, create deferred
                             to the next round; + the 6 replaced)
                 add 6
apply:  round 1  applied 29
        round 2  planned 32   → awaiting_approval   add 26   replace 9
                 invocations: action.turf_action.certify
apply:  round 2  … → awaiting_actions (certify)   → applied 35   invoked 1
converged in 2 round(s)
```

**All seventeen releases are condemned in the round of the replace**, including
the ten inside modules that defer whole — a release is deleted through the
configuration it was created with, and that configuration only exists while the
old cluster does. Round one uninstalls the seventeen releases from the old
cluster, destroys it, creates the new one and replaces the five shims that could
be planned; round two creates the seventeen releases in the new cluster,
re-asserts the readiness gate, pauses for `certify`, and replaces the nine shims
that were deferred. End state: one kind cluster (`aicr-2`), 17 releases
`deployed`, `ClusterPolicy` `ready`, fourteen shims all carrying the new
endpoint, and an idle `up` that plans nothing.

Compare stock Terraform on this same bundle (v1.16.2, measured 2026-10-13):
`Plan: 32 to add, 0 to change, 15 to destroy`. The fifteen replaced are the
cluster and the fourteen shims; the seventeen releases are *created*, because
the refresh that precedes the plan reported every one of them `has been
deleted`. They had not been — the plan runs against the old cluster — but the
helm provider's configuration is unknown while the cluster it reads from is
being replaced, and `hashicorp/helm`'s `Read` drops a release it cannot reach
from state on any failed existence check, which is how it treats an
unconfigured client. The apply then destroyed the cluster (5 s), created the
new one and installed seventeen releases into it: a correct end state, a clean
plan afterwards, and zero uninstalls. Here that does not matter, since
`kind delete` takes everything with it; on a cluster that outlives the
configuration it is seventeen orphaned releases, and the shim never got to
say otherwise. Given a cluster the plan *can* see, the shim does what it
says: bumping `cluster_keepers` on the live cluster planned all seventeen as
`replaced due to changes in replace_triggered_by`, seventeen uninstalls then
seventeen installs, the gate re-asserting at the end.

The mechanism is a plain destroy-then-create. The generated bundle carries no
`create_before_destroy`, so the old cluster is gone before the new one exists and
the stack is down for as long as round two takes to reinstall it. That is
Terraform's default replacement, explainable without reference to any engine.
The graceful variant — new cluster beside the old, releases moving across, the
old world deposed and deleted last — is what
[`terraform/kubernetes/kind-helm`](../../../terraform/kubernetes/kind-helm/README.md)
demonstrates with a hand-written stack, and it is one `lifecycle` line the
deployer could learn to emit.

**No wall-clock figure is quoted here on purpose.** Two clean runs of this exact
tree differed by a factor of three, and the difference is where you would expect:
round two is dominated by pulling sixteen charts' worth of images into a cluster
that was created seconds earlier. That number measures a laptop's network and
container runtime, not the engine and not the graph. The DAG-vs-waves figure
above is comparable precisely because it is derived from one run's own durations.

Ordering is observable in the cluster, not only in the plan — the five level-0
releases install within a few seconds of each other, `gpu-operator` only after all
three of its prerequisites, and `nvsentinel` / `nvidia-dra-driver-gpu` /
`kai-scheduler` last.

## The honest failure list

**A module that configures its own provider cannot be composed.** The default
`--deployer terraform` bundle is a *root* module: it declares `provider "helm"`
and takes the cluster connection as variables, which is right for applying
against a cluster that already exists. Calling that as a child module is a
different matter. Terraform accepts it but then forbids `depends_on`, `count`
and `for_each` on the call, and Turf refuses it outright:

```
this engine milestone does not walk provider blocks in child modules
(a legacy module shape; declare configuration_aliases and pass configurations
from the caller instead) (found: [helm]); the construct is refused rather than
skipped so a run cannot look complete while ignoring it
```

That refusal is the reason `bundle/` here is generated with
`--terraform-child-module`: no provider block, no connection variables, and the
root's `provider "helm"` — bound to `kind_cluster.dc` — is inherited. Which is
also what makes the cluster-in-the-graph story work at all.

**Terraform's experimental deferral refuses the containment shim.** `bundle/`
is generated with `--terraform-cluster-rollover`, so every component module
carries one `terraform_data` keyed on the cluster's endpoint, and every release
in it

```hcl
lifecycle {
  replace_triggered_by = [terraform_data.cluster]
}
```

— which is what makes a release be *replaced* when the cluster holding it is
replaced, instead of being adopted by a cluster that has never seen it. The
reference is to the resource as a whole, not to an attribute: the rule reads
"the shim is being replaced", a fact the plan knows structurally, rather than
"the endpoint changed", which cannot be evaluated while the endpoint is unknown.
`terraform_data` is built into Terraform (and into OpenTofu), so `hashicorp/helm`
is the bundle's only provider.

Stock Terraform plans and applies this tree in one round — `Plan: 32 to add` on
`v1.16.2`, cluster included, because `helm_release` never contacts the API server
at plan time; the gate Job completes inside the apply, in 90 s here, with
`ClusterPolicy` `ready` behind it. OpenTofu `v1.13.1` is the same at every
step. Measured 2026-10-13 on this bundle, single-node kind, one engine at a time:

| | Terraform v1.16.2 | OpenTofu v1.13.1 |
|---|---|---|
| create from empty | `32 to add`, one apply, 17 releases, gate `Complete` | same |
| idle plan | `No changes` | same |
| `generation=2` | `32 to add, 15 to destroy`: refresh reports the releases deleted, cluster and shims replaced, 17 created in the new cluster, 0 uninstalls | same |
| keeper bumped, cluster kept | `31 to add, 31 to destroy`: 17 `replaced due to changes in replace_triggered_by`, 17 uninstalls then 17 installs, new gate Job | same |
| destroy | `32 destroyed`, cluster gone | same |

Wall-clock is deliberately not in the table (see the note under *Replacing the
cluster*); for scale, a create ran 281 s on an idle laptop and 1192 s on a busy one. The experimental deferred-actions path is the one that fails:

```
$ terraform plan -allow-deferral
Plan: 6 to add, 0 to change, 0 to destroy.

Error: no change found for terraform_data.cluster in module.stack.module.network_operator
Error: no change found for terraform_data.cluster in module.stack.module.agentgateway
Error: no change found for terraform_data.cluster in module.stack.module.kube_prometheus_stack
```

Reproduced on `v1.17.0-alpha20260827` and on a source build of `main`
(`v1.18.0-dev`, re-run 2026-09-20 against this bundle). It needs both halves — a
`replace_triggered_by` *and* a referent that is itself deferred; drop either and
the plan succeeds. Terraform's transitive deferral is otherwise correct, and its
two reasons read almost exactly like the engine's (`because the provider
configuration is unknown`, `because a prerequisite for this resource is
deferred`). **Regenerate without `--terraform-cluster-rollover` and experimental
Terraform converges this tree too** — at the cost of the containment the shim
exists to provide. That is why the flag is off by default upstream.

**`kai-scheduler` returns before its pods are up.** AICR lists it as
asynchronous — `helm --wait` times out on its custom-resource readiness even
though every pod started — so the deployer emits `wait = false` and
`timeout = 1200` on that one module call, with the reason inline. Expect a
handful of `ContainerCreating` pods for ~30s after `up` returns. AICR keeps that
list in one table shared by `deploy.sh`, the helmfile deployer and this one, so
it is no longer something a consumer has to rediscover.

**Helm's `--wait` is not a readiness gate for custom resources.** Every edge here
is a workload gate, which is all `helm_release`'s `wait` can offer. AICR's answer
for status-level readiness is a chainsaw gate Job, and `--deployer terraform`
supports it: `aicr bundle --readiness-hooks` adds a `<component>-readiness`
release as the last slot in that component's module, so every dependent already
waits for it. The slot ignores the bundle-wide `wait` variable — an async
component may skip waiting on its own workloads, never on its gate.

The committed bundle is generated **with** the flag. `gpu-operator` in this
recipe ships a `readiness.yaml` asserting `ClusterPolicy` `status.state: ready`,
so the bundle carries a seventeenth folder, `012-gpu-operator-readiness`, as a
slot on `module.gpu_operator` — which its three dependents already wait for.
On a fresh cluster the gate Job completes in about 90 s: it polls the
`ClusterPolicy` through a stability window and passes once the operator has
settled on `ready` (`reason=NoGPUNodes` here), and `kai-scheduler`,
`nvidia-dra-driver-gpu` and `nvsentinel` install after it.

One thing to know about the gate's image. AICR tags it with the bundler version
and publishes it **only on release tags**; a build from source stamps `dev` and
falls back to `ghcr.io/nvidia/aicr-gate:dev`, a local-only tag that does not
exist in the registry. The bundle here is therefore generated by a build of the
fork stamped `v1.0.0` (see *Regenerating*), so the gate pins the published
`ghcr.io/nvidia/aicr-gate:v1.0.0` and pulls anonymously like everything else.

**A gate re-runs on every upgrade of its own release, and on nothing else.** A
Job's `spec.template` is immutable, so an upgrade rendering the same Job patches
nothing and leaves the original UID. So the gate Job is a Helm
`post-install,post-upgrade` hook with `hook-delete-policy: before-hook-creation`:
Helm deletes the previous Job, runs a fresh one, and blocks until it finishes.
The hook is also what holds the release open, so the slot sets `wait` but not
`wait_for_jobs` — a hook is not a release resource, and `deploy.sh` passes
`--wait` without `--wait-for-jobs` for the same reason.

What the hook cannot do is fire when the *component* changes. `helm_release`
tracks a local chart's **path, version and values**, not its rendered manifests,
so a gate whose own inputs are unchanged plans clean and is never upgraded at
all. Closing that means the gate release carrying something that moves with the
component — a digest of its rendered content, and the component's
`metadata.revision`. That was built and measured on the fork's earlier superset
branch ([turfbuild/aicr#1](https://github.com/turfbuild/aicr/pull/1): changing
`gpu-operator`'s values planned `0 to add, 2 to change`, both slots updated in
place, and the gate's Job came back with a new UID). It is deliberately **not**
in the submission, so this bundle does not have it.

**A change to bundled chart content does not reach the plan.** The same
property, seen from the other side: add a manifest to a `-post` wrapper's
`templates/` and re-plan — `No changes`, while the bundle on disk differs from
what is deployed. The per-slot content digest that fixes this rode on the same
superset branch and is deferred from the submission as its own change. Until it
lands, an edit to bundled content needs a taint on that slot to reach the
cluster.

**`helm uninstall` leaves CRDs behind**, as always. `destroy` removes the cluster, so
it does not matter here; it would on a cluster you keep.

## Certification and handover

`aicr.turf.hcl` adds the two steps a person or an agent performs around the
stack, as Turf actions — `turf_action`, the built-in action the agent driving
Turf carries out itself. tofu and terraform ignore the file by its name; Turf
lays it over the configuration at every plan, and `up` lists the invocations
beside the resource changes (`plan.invocations`).

- **`certify`** is bound to the GPU Operator's release, `after_create`. When
  that release lands the apply stops at `awaiting_actions`: the agent reads the
  `ClusterPolicy`, fails unless it is `ready`, and reports the node and GPU
  census — zero GPUs and `reason=NoGPUNodes` here, the one label between this
  laptop and a datacenter. A failure taints the release, so the next `up`
  replaces it.
- **`handover`** is declared but bound to nothing: a decision only the operator
  makes, run when the cluster is ready to leave your hands —
  `invoke({ action_addr: "action.turf_action.handover" })`. The agent asks the
  user and reports their words; a "no" is a failure carrying their reason.

`worker_count` (default 0) adds kind worker nodes beside the control plane.
kind lifts the control plane's `NoSchedule` taint only on a single-node
cluster, so with workers every workload lands on them; `2` is the smallest
count that lets one be drained, which is what
[`terraform/kubernetes/node-maintenance`](../../../terraform/kubernetes/node-maintenance/README.md)
does to this cluster for day 2.

## Layout

```
versions.tf              the kind + helm providers; helm bound to kind's outputs
main.tf                  kind_cluster.dc, and the one module call for the bundle
aicr.turf.hcl            Turf actions: certify (after the GPU Operator) and handover (invoke)
variables.tf             cluster name, generation, node image, worker count
outputs.tf               passthrough of the bundle's own outputs
bundle/                  ALL generated by `aicr bundle --deployer terraform`
  main.tf                  one module call per component, carrying the graph
  versions.tf              required_providers; no provider block (child module)
  variables.tf outputs.tf
  modules/component/       one component: its chart, plus pre/post/gate slots
  NNN-<component>/         values.yaml and cluster-values.yaml, plus a local
                           chart where the component bundles one
  recipe.yaml              the resolved recipe this was generated from
  bundle-info.yaml         the index: every release, its component and its folder
  checksums.txt README.md
```

`bundle/` is committed so the example runs without an `aicr` binary on your PATH.
`bundle/002-agentgateway-crds-post/templates/` is the bulk of it — vendored
Gateway API CRDs that belong to the upstream chart, not to this repository.

## Regenerating

```sh
aicr bundle --recipe bundle/recipe.yaml --output bundle \
  --deployer terraform --terraform-child-module --terraform-cluster-rollover \
  --readiness-hooks
```

That is the whole thing. `--deployer terraform` is not in a released AICR yet.
The bundle here is generated by the submission,
[NVIDIA/aicr#3217](https://github.com/NVIDIA/aicr/pull/3217)
(fork branch [turfbuild/aicr#3](https://github.com/turfbuild/aicr/pull/3), head
`3a19de57`), written against the same `Deployer` interface the other five
renderers implement, on top of NVIDIA's v1.0.0 line. The binary was built from
that head stamped as the release it sits on —

```sh
go build -ldflags "-X github.com/NVIDIA/aicr/pkg/cli.version=v1.0.0" -o aicr ./cmd/aicr
```

— which is why `bundle/` says `Generated by AICR v1.0.0` and why the readiness
gate's image resolves (see *Helm's `--wait` is not a readiness gate* above).
The fork's earlier superset branch
([turfbuild/aicr#1](https://github.com/turfbuild/aicr/pull/1)) carried the
content digests as well; those are split out to follow.

The generated `.tf` is emitted already `terraform fmt`-clean, so the command
above reproduces the committed bytes exactly — regenerate and `git diff` to check
this directory is current.
