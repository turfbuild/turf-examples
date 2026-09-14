# NVIDIA GPU Cloud on a cluster with no GPU

Install the whole NVIDIA NGC cluster-side control plane — **GPU Operator** and
**NIM Operator** — onto a local `kind` cluster, with **cert-manager** and
**ExternalDNS** alongside. Four Helm charts behind four local modules, one
command, and **no credentials of any kind**.

The laptop has no NVIDIA GPU. That is the point of the example, not a caveat.

## What This Demonstrates

### Two operators, one label

Both operators come up healthy and then stop at exactly the same place, and both
say so out loud.

The GPU Operator's `ClusterPolicy`:

```
ready   NoGPUNodes: No GPU node found, watching for new nodes to join the cluster.
```

The NIM Operator, the moment you give it a `NIMCache`, builds a model-puller pod
carrying:

```yaml
nodeSelector:
  feature.node.kubernetes.io/pci-10de.present: "true"
```

`10de` is NVIDIA's PCI vendor ID, and that label is written by the Node Feature
Discovery instance the GPU Operator ships. **One label is the entire seam between
a laptop and a datacenter.** Everything upstream of it — CRDs, controllers,
webhooks, RBAC, reconcile loops — is identical to what a DGX cluster runs, and
you can install, inspect and tear it all down here. Everything downstream of it
needs real silicon.

On a node without the label the GPU Operator creates **no operand DaemonSets at
all** — not created-with-zero-replicas, absent. The only DaemonSet in
`gpu-operator` is NFD's own worker. Nothing crash-loops, nothing pends.

### The images are public. The models are not.

A common assumption about NGC is that nothing pulls without an NGC API key. For
the operators that is simply false, and the distinction is worth knowing:

| | Anonymous pull? |
| --- | --- |
| `helm.ngc.nvidia.com/nvidia` chart index | yes |
| `nvcr.io/nvidia/gpu-operator` | yes |
| `nvcr.io/nvidia/cloud-native/k8s-nim-operator` | yes (`imagePullSecrets` is empty by default) |
| `nvcr.io/nvidia/k8s-device-plugin` | yes |
| `nvcr.io/nim/nvidia/llm-nim` and friends | **no** — `DENIED` |

So the control plane is credential-free; only the **model** content behind a
`NIMCache` or `NIMService` needs a key. And on a GPU-less cluster you never even
reach that wall — the puller pod pends on the nodeSelector long before it tries
to pull.

### cert-manager is here because something needs it

Not because stacks usually have it. The NIM Operator's validating admission
webhook serves TLS, and the chart mints that certificate by creating a
cert-manager `Issuer` and `Certificate`. Its own `values.yaml` says so: *"cert-manager
must be installed beforehand, as it is required to generate the TLS
certificates."*

Set `enable_admission_controller = false` and the cert-manager module drops out
with it — the `count` is the honest statement of why it is in the stack.

With it on, the webhook enforces a rule the CRD schema cannot express:

```
admission webhook "vnimservice-v1alpha1.kb.io" denied the request:
nimservice.spec.storage: Invalid value: "multiple storage sources defined":
only one of .nimCache, .pvc, .emptyDir or .hostPath must be defined
```

A complete Issuer → Certificate → caBundle → readable-rejection chain, on a
laptop, with no credentials. (Note: a `NIMService` rejected for a missing
`authSecret` is CRD *schema* validation, not the webhook. The cross-field storage
rule is the one that proves the webhook is live.)

### Deferral

The `helm` provider is configured from the kind cluster's **computed** connection
details, which do not exist until the cluster is applied. All four releases are
therefore unplannable on the first walk. Vanilla OpenTofu needs two applies;
Turf defers them, applies the cluster, and re-plans against the now-known
connection.

### `wait = true` is not convergence

Every release sets `wait = true`, and helm honours it — but helm waits on
*workloads*, not on a CRD's status subresource. The GPU Operator's `ClusterPolicy`
reaches `ready` roughly **50 seconds after** helm has already reported the release
deployed. If you script anything against this stack, poll the `ClusterPolicy`, not
the release.

## The modules

Each wraps exactly one chart, in a single `main.tf` — `required_providers`, then
variables, then the release, then outputs.

| Module | Chart | Pin | Why it is here |
| --- | --- | --- | --- |
| `modules/gpu-operator` | `nvidia/gpu-operator` | `v26.7.0` | driver, toolkit, device plugin, DCGM — all of it gated on the NFD label |
| `modules/nim-operator` | `nvidia/k8s-nim-operator` | `3.1.2` | 9 CRDs: `NIMCache`, `NIMService`, `NIMPipeline`, `NIMBuild`, 5 × `Nemo*` |
| `modules/cert-manager` | `jetstack/cert-manager` | `v1.21.2` | the NIM webhook's serving certificate |
| `modules/external-dns` | `external-dns/external-dns` | `1.22.0` | what would publish a `NIMService` hostname; `inmemory` here |

Three details in those modules are load-bearing and easy to get wrong:

- **`external-dns` requires `policy`.** The chart ships no default and marks it
  `(REQUIRED)`; installing with pure defaults fails values-schema validation
  with `at '/policy': got null, want string`. The values key is `provider.name`,
  not `provider`.
- **`cert-manager` uses `crds.enabled`**, not the pre-v1.15 `installCRDs`.
- **Containment is declared, across a module boundary.** Each module carries a
  `null_resource` keyed on the cluster endpoint, and its release declares
  `replace_triggered_by` against it. A release lives *inside* the cluster:
  replacing the cluster without saying so annihilates it with no provider RPC —
  helm never runs its uninstall, no hooks fire — leaving a state entry pointing
  at nothing. A module cannot name a resource in its caller and
  `replace_triggered_by` only accepts same-module references, so the caller
  passes the endpoint in and the module turns it into something the release can
  point at. (`null_resource` rather than the modern `terraform_data`: Turf does
  not serve the built-in `terraform` provider.)

## Resources Created

- `kind_cluster.dc` — a local Kubernetes cluster running as Docker containers.
- `module.gpu_operator` / `module.nim_operator` — the two NGC operators.
- `module.cert_manager[0]` — present only when `enable_admission_controller`.
- `module.external_dns[0]` — present only when `enable_external_dns`.

Nine addresses, nine pods, ~2.7 GB of images.

## Prerequisites

- Docker, `kind`, and `kubectl` on your PATH.
- The Turf CLI, or any MCP client pointed at `turf-mcp-server`.
- **No NGC account, no API key, no cloud credentials.**
- If you run **more than one container engine** (OrbStack *and* Docker Desktop,
  say), pin the one you mean before starting — `kind` silently builds into
  whichever context is current, and the two have different CPU/RAM budgets:
  ```bash
  export DOCKER_CONTEXT=orbstack
  ```

## Usage

```bash
turf -C use-cases/datacenter/ngc-stack up
```

One command: Turf plans, defers the four releases, applies the cluster, and
re-converges. Expect roughly 5–6 minutes on a cold image cache.

## Verify

```bash
CTX=kind-$(turf -C use-cases/datacenter/ngc-stack output -raw cluster_name)

# Nine pods, nothing crash-looping.
kubectl --context $CTX get pods -A

# The GPU Operator, waiting for silicon that will never arrive.
kubectl --context $CTX get clusterpolicy -o jsonpath='{.items[0].status.conditions[0].message}'
#   No GPU node found, watching for new nodes to join the cluster.

# Nobody carries the label. This is the seam.
kubectl --context $CTX get nodes -l feature.node.kubernetes.io/pci-10de.present=true
#   No resources found

# NFD did look — 45 other feature labels prove it.
kubectl --context $CTX get node -o json | jq '[.items[0].metadata.labels|keys[]|select(startswith("feature.node"))]|length'

# Only NFD's worker. No NVIDIA operands were created.
kubectl --context $CTX -n gpu-operator get ds

# The NIM Operator's 9 CRDs.
kubectl --context $CTX get crd | grep -E 'nim|nemo'

# cert-manager issued the webhook's serving cert, and the caBundle is injected.
kubectl --context $CTX -n nim-operator get certificate,issuer
```

And the demo worth actually running — the webhook rejecting a bad CR:

```bash
kubectl --context $CTX apply -f - <<'YAML'
apiVersion: apps.nvidia.com/v1alpha1
kind: NIMService
metadata: {name: rejected, namespace: nim-operator}
spec:
  authSecret: ngc-api-secret
  image: {repository: nvcr.io/nim/meta/llama-3.2-1b-instruct, tag: "1.8.6"}
  replicas: 1
  storage:
    nimCache: {name: none, profile: ""}
    pvc: {create: true, size: 5Gi, volumeAccessMode: ReadWriteOnce}
YAML
# Error from server (Forbidden): admission webhook "vnimservice-v1alpha1.kb.io"
# denied the request: ... only one of .nimCache, .pvc, .emptyDir or .hostPath
```

### Watching a NIMCache pend

If you want to see the seam from the NIM side, apply a `NIMCache`. It needs no
valid credentials to make the point — the operator creates the PVC, creates the
puller pod, and the pod pends forever on the nodeSelector. The operator itself
stays `Running`; nothing crash-loops.

```bash
kubectl --context $CTX apply -f - <<'YAML'
apiVersion: apps.nvidia.com/v1alpha1
kind: NIMCache
metadata: {name: pending-forever, namespace: nim-operator}
spec:
  source:
    ngc:
      authSecret: ngc-api-secret          # does not exist; never reached
      modelPuller: nvcr.io/nim/meta/llama-3.2-1b-instruct:1.8.6
      pullSecret: ngc-secret
      model: {engine: tensorrt_llm}
  storage:
    pvc: {create: true, size: 5Gi, storageClass: standard, volumeAccessMode: ReadWriteOnce}
YAML

kubectl --context $CTX -n nim-operator describe pod pending-forever-pod | tail -5
#   Warning  FailedScheduling  0/1 nodes are available:
#   1 node(s) didn't match Pod's node affinity/selector.
```

`volumeAccessMode` is not marked required by the CRD, but the operator cannot
build a valid PVC without it — omit it and you get a `NIM_CACHE_RECONCILE_FAILED`
condition instead.

Delete it before destroying: `kubectl --context $CTX -n nim-operator delete nimcache pending-forever`.

## Cleanup

```bash
turf -C use-cases/datacenter/ngc-stack destroy
```

Destroying the cluster takes everything with it, so nothing survives locally. If
you instead uninstall the releases against a cluster you are keeping, know that
**helm leaves CRDs and namespaces behind** — that is standard helm behaviour, not
a bug:

```bash
kubectl delete crd $(kubectl get crd -o name | grep -E 'nvidia|nfd\.k8s-sigs|cert-manager')
kubectl delete ns gpu-operator nim-operator cert-manager external-dns
```

## Pointing this at real GPUs

The modules are the same; the variables change.

```hcl
# On a node pool whose image ships no driver or container runtime config:
gpu_driver_enabled  = true
gpu_toolkit_enabled = true
```

Then point the `helm` provider at that cluster instead of `kind_cluster.dc`, and
for actual inference add the two NGC secrets the model tier needs — an
`ngc-api-secret` (the API key, read by the operator) and an `ngc-secret`
(a docker-registry pull secret for `nvcr.io`) — and reference them from your
`NIMCache`/`NIMService`. Those are the only parts of this example that need an
NGC account, and they are deliberately not created here.

The GPU Operator's `ClusterPolicy` will switch off `NoGPUNodes` on its own the
moment a labelled node joins; it is already watching.

## Notes on Turf's Restate engine

This example runs on both Turf engines, but the Restate engine constrains the
HCL in two ways worth knowing if you write your own:

- **Modules must live under the configuration directory.** `source =
  "../modules/cert-manager"` is refused — *"this engine walks the directory a
  user names and what lives under it"* — which is why `modules/` sits inside
  `ngc-stack/` rather than being shared across the `use-cases/datacenter/` tree.
- **`depends_on` on a module call is refused**, loudly rather than silently
  ignored. The NIM module therefore takes an `upstream` list of release ids and
  references it, which is a stronger statement anyway: those releases are not
  merely earlier, they are what this one is built on. The reference has to land
  on the `helm_release` rather than on the module's `null_resource`, because the
  upstream releases are themselves deferred and the engine will not apply a
  resource ordered after a deferred one.

The edge is visible in the cluster, which is a nice side effect:

```
$ helm -n nim-operator history nim-operator
1  deployed  k8s-nim-operator-3.1.2  NVIDIA NIM Operator — installed after cert-manager, gpu-operator
```
