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
together — create a kind cluster and hand it to the generated bundle. Sixteen
Helm releases come up behind it, from nothing, in one command.

```
turf -C use-cases/datacenter/aicr-stack up
```

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
releases — 16 releases here for 14 components — and those chain **inside** the
component's module. So `depends_on = [module.agentgateway_crds]` covers that
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

Sixteen releases, seven registries — `nvcr.io`, `cr.agentgateway.dev`,
`ghcr.io/nvidia/nodewright`, `ghcr.io/nvidia/nvsentinel`, `ghcr.io/kai-scheduler`,
`registry.k8s.io/dra-driver-nvidia`, `charts.jetstack.io` and the Prometheus
community charts — and **no key, no secret, no `imagePullSecrets`**. This was the
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

Measured on the **Restate engine** (`turf-engine` at `0076f5d`, driven by
`turf-driver up --converge`), from empty state. Unlike
[`../ngc-stack`](../ngc-stack/README.md), this example has **not** been run on
the shipping MCP engine.

Round one can plan and apply exactly six addresses — the cluster and the five
containment shims that sit behind no order-only edge. Everything else defers,
and nine of the fourteen components defer **whole**:

```
plan for phase p-3251d18f (30 of 30 address(es) change):
  create    kind_cluster.dc
  create    module.stack.module.cert_manager.null_resource.cluster
  unspecified module.stack.module.cert_manager.helm_release.this  (deferred)
  unspecified module.stack.module.cert_manager.helm_release.post  (deferred)
  unspecified module.stack.module.cert_manager.helm_release.readiness  (deferred)
  ...
  unspecified module.stack.module.gpu_operator  (whole module deferred: absent_prereq)
  unspecified module.stack.module.nvsentinel    (whole module deferred: absent_prereq)

phase p-3251d18f: applied (applied 6, failed 0, cancelled 0)
round 1 deferred 24 entry(ies); planning again against the committed state
plan for phase p-c914e200 (25 of 31 address(es) change):
phase p-c914e200: applied (applied 25, failed 0, cancelled 0)
converged in 2 round(s)
```

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
`helm_release.this`. They collapse to zero instances in round two. The cost is a
noisier first plan: 30 entries rather than the 16 releases plus 14 shims plus the
cluster that actually exist.

`turf -C use-cases/datacenter/aicr-stack destroy` removes all 31 addresses in a
single phase.

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
and `for_each` on the call, and the Restate engine refuses it outright:

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

**Stock Terraform cannot plan this configuration, because of the containment
shim.** `bundle/` is generated with `--terraform-cluster-rollover`, so every
component module carries

```hcl
lifecycle {
  create_before_destroy = true
  replace_triggered_by  = [null_resource.cluster]
}
```

— which is what makes a release be *replaced* when the cluster holding it is
replaced, instead of being adopted by a cluster that has never seen it. Combined
with deferral, Terraform's experimental deferred-actions path fails:

```
$ terraform plan -allow-deferral
Plan: 6 to add, 0 to change, 0 to destroy.

Error: no change found for null_resource.cluster in module.stack.module.kube_prometheus_stack
Error: no change found for null_resource.cluster in module.stack.module.agentgateway_crds_post
Error: no change found for null_resource.cluster in module.stack.module.network_operator
```

Reproduced on `v1.17.0-alpha20260827` and on a source build of `main`. It needs
both halves — a `replace_triggered_by` *and* a referent that is itself deferred;
drop either and the plan succeeds. Terraform's transitive deferral is otherwise
correct, and its two reasons read almost exactly like the engine's
(`because the provider configuration is unknown`,
`because a prerequisite for this resource is deferred`). **Regenerate without
`--terraform-cluster-rollover` and experimental Terraform converges this tree
too** — at the cost of the containment the shim exists to provide. That is why
the flag is off by default upstream.

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

The committed bundle is generated **without** the flag. Not for lack of a gate to
run: `gpu-operator` in this very recipe ships a `readiness.yaml` asserting
`ClusterPolicy` `status.state: ready`, and regenerating with `--readiness-hooks`
yields a seventeenth folder, `012-gpu-operator-readiness`, as a slot on
`module.gpu_operator` — which its three dependents already wait for.

The reason is the gate's own image. AICR tags it with the bundler version, and
publishes it **only on release tags**; a build from source stamps `dev` and falls
back to `ghcr.io/nvidia/aicr-gate:dev`, which is a local-only tag you are expected
to build and `kind load` yourself (`ghcr.io/nvidia/aicr-gate:dev` → HTTP 404). Since
`--deployer terraform` exists only on a fork branch, there is no released `aicr`
that can emit both the terraform bundle and a pullable gate. Committing the flag
on would ship a bundle that `ImagePullBackOff`s on any machine but the one that
built it — so it stays off until the deployer lands in a release.

It has been run, though, on a build of this tree with the gate image loaded by
hand: the gate polls `gpu-operator`'s `ClusterPolicy` through a stability window
and passes at `T+30s`, and its three dependents wait for it.

**A gate re-runs when, and only when, its component changes** — and it does so
without the release ever being replaced. Two facts make that hard. A Job's
`spec.template` is immutable, so an upgrade rendering the same Job patches
nothing and leaves the original UID; and `helm_release` tracks a local chart's
**path, version and values**, not its rendered manifests, so editing a template
under `NNN-<component>/templates/` produces no plan at all.

So the gate Job is a Helm `post-install,post-upgrade` hook with
`hook-delete-policy: before-hook-creation`: Helm deletes the previous Job, runs a
fresh one, and blocks until it finishes. And the gate release carries two signals
that make it *upgrade* in the first place — a digest of its own rendered content
in `description`, and the component's `metadata.revision` in `values`.

Replacement was the obvious mechanism and it is the wrong one: this slot inherits
`create_before_destroy` from its siblings under `--terraform-cluster-rollover` and
cannot decline it, so a replacement installs the new release while the old one
still holds the name, in the same cluster, and Helm refuses it.

Measured here with the flag on (2026-09-18, Terraform v1.16.2): re-applying
unchanged is `No changes`; changing `gpu-operator`'s values is `0 to add, 2 to
change, 0 to destroy` — `helm_release.this` and `helm_release.readiness[0]` both
**updated in place** — the gate's Job comes back with a new UID, and the other
thirteen components' gates stay put.

**Content changes reach the plan at all** because of those digests, which is a
property of every bundled chart and not only of gates. Add a manifest to a
`-post` wrapper's `templates/` and re-plan: `No changes`. Regenerate, so the
`post_digest` argument moves with it, and the same edit is
`helm_release.post[0] will be updated in-place` — and the object lands in the
cluster.

**`helm uninstall` leaves CRDs behind**, as always. `down` removes the cluster, so
it does not matter here; it would on a cluster you keep.

## Layout

```
versions.tf              the kind + helm providers; helm bound to kind's outputs
main.tf                  kind_cluster.dc, and the one module call for the bundle
variables.tf             cluster name, generation, node image
outputs.tf               passthrough of the bundle's own outputs
bundle/                  ALL generated by `aicr bundle --deployer terraform`
  main.tf                  one module call per component, carrying the graph
  versions.tf              required_providers; no provider block (child module)
  variables.tf outputs.tf
  modules/component/       one component: its chart, plus pre/post/gate slots
  NNN-<component>/         values.yaml, cluster-values.yaml, and either
                           upstream.env or a local chart
  recipe.yaml              the resolved recipe this was generated from
  checksums.txt README.md
```

`bundle/` is committed so the example runs without an `aicr` binary on your PATH.
`bundle/002-agentgateway-crds-post/templates/` is the bulk of it — vendored
Gateway API CRDs that belong to the upstream chart, not to this repository.

## Regenerating

```sh
aicr bundle --recipe bundle/recipe.yaml --output bundle \
  --deployer terraform --terraform-child-module --terraform-cluster-rollover
```

That is the whole thing. `--deployer terraform` is not in NVIDIA's AICR yet — it
is [turfbuild/aicr#1](https://github.com/turfbuild/aicr/pull/1), a fork branch
written against the same `Deployer` interface the other five renderers implement,
pending a decision on proposing it upstream.

The generated `.tf` is emitted already `terraform fmt`-clean, so the command
above reproduces the committed bytes exactly — regenerate and `git diff` to check
this directory is current.
