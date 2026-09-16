# An AICR recipe, deployed as the graph it actually is

Nothing in this directory was written by hand. The `.tf` files below were
**generated** from a single [NVIDIA AI Cluster Runtime](https://github.com/NVIDIA/aicr)
(AICR) recipe, and that is the point of the example.

AICR publishes validated, version-locked combinations of GPU drivers, operators
and system configuration as *recipes*, and renders them for Helm, Argo CD, Flux
or Helmfile. It is explicit that it is **not a cluster provisioner** — "you bring
your GPU-accelerated Kubernetes cluster and your deployment tooling." That
boundary is a hard edge in everything it emits: the cluster is a precondition,
never a node in the graph.

Terraform is the one consumer that can put the cluster *in* the graph. This stack
creates a kind cluster and installs sixteen Helm releases behind it, from nothing,
in one command.

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

Each component carries a `dependencyRefs` list. The generator turns that list —
and nothing else — into `depends_on` between module calls:

```hcl
module "gpu_operator" {
  source = "./modules/component"
  ...
  depends_on = [module.cert_manager, module.kube_prometheus_stack, module.nfd]
}
```

A recipe also ships a precomputed flat `deploymentOrder`. **The generator ignores
it.** That field is a linearisation of the graph above, and handing a
linearisation to an engine built to schedule graphs throws away the only thing
worth carrying.

Which matters, because most of AICR's own renderers cannot carry it. `helm` emits
a line of sixteen. `argocd` emits sync-waves 1/5/9/13 and `helmfile` emits nested
`level-0…3.yaml` — both of which are *barriers*, not edges. Only `flux` emits the
real per-release `dependsOn`, and Flux is an in-cluster reconciler that cannot
create the cluster it reconciles into.

### What a barrier costs

Measured, on one `helmfile sync` of this very bundle. helmfile reports a
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
comparison of scheduling models over measured durations, not a measured race.)

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
               "No GPU node found, watching for new nodes to join the cluster."
no feature.node.kubernetes.io/pci-* labels on the node
```

The GPU Operator creates **no** operand DaemonSets at all. The two components
that are new here relative to the NGC stack both land cleanly rather than
crashlooping — they create DaemonSets that sit at zero:

```
nvidia-dra-driver  nvidia-dra-driver-gpu-kubelet-plugin  desired=0 ready=0
nvsentinel         gpu-health-monitor-dcgm-{3,4}.x       desired=0 ready=0
nvsentinel         metadata-collector                    desired=0 ready=0
nvsentinel         syslog-health-monitor-{kata,regular}  desired=0 ready=0
nvsentinel         platform-connectors                   desired=1 ready=1
```

One Node Feature Discovery label is still the entire seam between this laptop and
a datacenter.

Note the recipe's kind overlay is written for **nvkind** — it sets
`driver.enabled: false` and `nvsentinel.labeler.assumeDriverInstalled: true`
because it assumes a driver installed on the host. On a plain kind cluster that
assumption is simply unmet, and the result is the clean idle above rather than an
error.

## What it does when you run it

Measured on the **Restate engine** (`turf-engine` at `259dbca`, driven by
`turf-driver up --converge`), from empty state. Unlike
[`../ngc-stack`](../ngc-stack/README.md), this example has **not** been run on
the shipping MCP engine — every engine number below is from the Restate engine
only.

```
round 1: reconcile 415ms | plan 7.6s  | apply 44.1s  | total 52.9s
round 2: reconcile 414ms | plan 24.5s | apply 2m9.5s | total 2m34.8s
converged in 2 round(s)
```

Round one can only build the cluster and the five containment shims that do not
sit behind an order-only edge. Everything else defers, and eleven of the sixteen
modules defer **whole**:

```
plan for phase p-47829b94 (22 of 22 address(es) change):
  create    kind_cluster.dc
  create    module.cert_manager.null_resource.cluster
  unspecified module.cert_manager.helm_release.this  (deferred)
  ...
  unspecified module.gpu_operator  (whole module deferred: absent_prereq)
  unspecified module.nvsentinel    (whole module deferred: absent_prereq)
```

`absent_prereq` is the engine saying a module is deferred because it depends —
transitively, over an edge that carries no value — on something else that is
deferred. Round two plans all 27 remaining addresses at once and applies them.
Note that the DAG is four deep but converging costs **two** rounds, not four:
deferral is about unknown *values*, not about graph depth. Once the cluster
exists, the helm provider's configuration is known and the whole graph is
plannable; ordering is then just the graph, inside one apply.

`turf -C use-cases/datacenter/aicr-stack destroy` removes all 33 addresses in a
single phase.

Ordering is observable in the cluster, not only in the plan — the five level-0
releases install within four seconds of each other, `gpu-operator` only after all
three of its prerequisites, and `nvsentinel` / `nvidia-dra-driver-gpu` /
`kai-scheduler` last.

## The honest failure list

**Stock Terraform cannot plan this configuration.** Every module here carries the
usual containment shim —

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

Error: no change found for null_resource.cluster in module.kube_prometheus_stack
Error: no change found for null_resource.cluster in module.agentgateway_crds_post
Error: no change found for null_resource.cluster in module.network_operator
```

Reproduced on `v1.17.0-alpha20260827` and on a source build of `main`. It needs
both halves — a `replace_triggered_by` *and* a referent that is itself deferred;
drop either and the plan succeeds. Terraform's transitive deferral is otherwise
correct, and its two reasons read almost exactly like the engine's
(`because the provider configuration is unknown`,
`because a prerequisite for this resource is deferred`). Deleting the `lifecycle`
block from `modules/component/main.tf` makes this tree converge on Terraform in
two rounds as well — at the cost of the containment the block exists to provide.

**`kai-scheduler` returns before its pods are up.** It is the one component the
generator marks `wait = false`, because AICR lists it as asynchronous: `helm
--wait` times out on its custom-resource readiness even though every pod started.
Expect a handful of `ContainerCreating` pods for ~30s after `up` returns. AICR
keeps that list in a shell template rather than in the recipe schema, so every
consumer that is not `deploy.sh` has to hardcode it; the generator does.

**Helm's `--wait` is not a readiness gate for custom resources.** Every edge here
is a workload gate, which is all `helm_release`'s `wait` can offer. AICR's own
answer for status-level readiness is a chainsaw gate Job (`--readiness-hooks`),
and no component in *this* recipe needs one — but `network-operator` plus
`gpu-operator` with RDMA would.

**`helm uninstall` leaves CRDs behind**, as always. `down` removes the cluster, so
it does not matter here; it would on a cluster you keep.

## Layout

```
versions.tf              providers + the helm provider bound to kind's outputs
main.tf                  kind_cluster.dc, then 16 module calls with depends_on
variables.tf             cluster name, generation, node image
outputs.tf               every release id
modules/component/       one AICR component = one helm_release + a containment shim
bundle/                  the AICR bundle: per-component values.yaml, upstream.env
                         or a local chart, plus recipe.yaml and the helmfile the
                         DAG-vs-waves numbers above came from
```

`bundle/` is generated output, committed so the example runs without an `aicr`
binary on your PATH. `bundle/002-agentgateway-crds-post/templates/` is the bulk
of it — vendored Gateway API CRDs that belong to the upstream chart, not to this
repository.

## Regenerating

The generator is a ~250-line Go program against AICR's integrator surface
(`pkg/client/v1`): `ResolveRecipeFromCriteria` → `MakeBundle` → emit HCL. It does
not live in this repository yet. What it needs from the SDK, and the two places
the SDK could not supply it:

- `aicr.ComponentRef` does **not** carry `DependencyRefs`. A generator whose whole
  subject is the dependency graph has to call `RecipeResult.Resolved()` and reach
  into `pkg/recipe`, which AICR's own roadmap (#2016) says an integrator should
  not have to do.
- `BundleOptions.Deployer` is typed `config.DeployerType`, so naming a deployer
  means importing `pkg/bundler/config` as well.

The natural home for this is upstream as `--deployer terraform`, alongside the
five renderers AICR already ships. The `Deployer` interface is a single method.

The `.tf` files here have been run through `terraform fmt`; the generator's raw
output is not yet fmt-clean.
