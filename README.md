# turf-examples

Reference Terraform/HCL examples and agent integrations for
[Turf](https://github.com/turfbuild/turf) — a drop-in replacement for Terraform
with agentic superpowers, exposed as an infrastructure MCP server.

Every artifact here consumes the Turf MCP server only through the MCP protocol or
through ordinary Terraform HCL — there are no Go imports of Turf internals.

## Layout

```
terraform/        Standard Terraform/HCL configurations (tofu dialect)
  kubernetes/
    kind-crd/       kind cluster → CustomResourceDefinition → custom resource
    kind-helm/      kind cluster → Helm release (podinfo)
    hpa-walkthrough/  php-apache + HorizontalPodAutoscaler on an existing cluster
  aws/
    lambda-fleet/   a fleet of Lambda functions, patched in place by one variable
  azure/
    avm-resourcegroup/   multi-instance Azure resource groups via a published AVM module
  gcp/
    gke-demo/       GKE Autopilot cluster with custom VPC networking
  language/         Terraform language & feature demos
    actions/        Terraform Actions — action blocks + lifecycle.action_trigger
    two-phase/      staged-then-commit convergence (stretch/advanced)
    replace-ordering/  replacement teardown ordering + infectious create-before-destroy

turf/             Turf-specific examples — the plot dialect + Turf-native features
  language/
    plot-dialect/   plot units (*.tfplot.hcl) authored by declare_*, then config_promote
    local-module/   a plot that calls a local module by a portable relative source
    turf-actions/   Turf-native actions — turf_confirm (human) + turf_action (agent)

use-cases/        End-to-end stacks for a real domain, composed from local modules
  datacenter/
    ngc-stack/      NVIDIA GPU Cloud — GPU Operator + NIM Operator + cert-manager
                    + ExternalDNS on a kind cluster with no GPU
    aicr-stack/     NVIDIA AI Cluster Runtime — 16 Helm releases generated from
                    one AICR recipe, deployed as the dependency graph it declares

integrations/     How to drive turf-mcp-server from different agent runtimes
  kagent/             Kubernetes manifests: MCPServer, Agent, RBAC, PVC, ModelConfig
  turf-cli/           Configuring the standalone Turf CLI (.turf/): user skills
                      + model config (turf.yaml — first-available, named, local)
  kubernetes-backend/ Store Turf state in-cluster via the kubernetes state backend
  scalr/              Turf tailored for Scalr: remote backend, setup-as-code,
                      OPA policy, module registry, and MCP read-back
```

## Terraform examples

Each `terraform/<...>` directory is a self-contained **tofu** configuration — plain
hand-authored `.tf` files. Drive it with the Turf CLI (`turf -C <dir> up`) or the MCP
tools (`config_init` against the directory, then `plan_new` — its initial walk plans
the whole tree). See each example's `README.md` for prerequisites, usage, and cleanup.

| Example                        | Providers                     | Local? | Notes                                              |
|--------------------------------|-------------------------------|--------|----------------------------------------------------|
| `kubernetes/kind-crd`          | tehcyx/kind, hashicorp/kubernetes | ✅ | CRD-then-CR convergence in one run                 |
| `kubernetes/kind-helm`         | tehcyx/kind, hashicorp/helm (v3+) | ✅ | Helm release on a local kind cluster               |
| `kubernetes/hpa-walkthrough`   | hashicorp/kubernetes          | ⎈ | HPA walkthrough — `ignore_changes` on replicas     |
| `aws/lambda-fleet`             | hashicorp/aws, hashicorp/archive | ☁️ AWS | fleet of Lambdas patched in place (`count`)        |
| `azure/avm-resourcegroup`      | hashicorp/azurerm + AVM module | ☁️ Azure | multi-instance keyed modules (`for_each`/`count`) |
| `gcp/gke-demo`                 | hashicorp/google              | ☁️ GCP | GKE Autopilot + custom VPC                         |
| `language/actions`             | hashicorp/tfcoremock, hashicorp/local | ✅ | Terraform Actions (gating invokes)          |
| `language/two-phase`           | hashicorp/tfcoremock          | ✅ | staged-then-commit via actions (advanced)          |
| `language/replace-ordering`    | hashicorp/random              | ✅ | replace teardown ordering + infectious CBD         |

✅ = credential-free / local. ☁️ = needs a cloud account. ⎈ = needs an existing
Kubernetes cluster + kubeconfig.

## Turf examples

The `turf/` tree exercises capabilities specific to Turf. Most are **plots** —
turf-authored `*.tfplot.hcl` units, one per address, written by the `declare_*` tools
from an ad-hoc session (`config_init` reports the dialect). `config_promote` graduates
a plot into an ordinary tofu configuration — a one-way, walk-equivalent strip-fold-rename.
Drive them the same way (`turf -C <dir> up`); all are credential-free.

| Example                     | Providers            | Notes                                                              |
|-----------------------------|----------------------|--------------------------------------------------------------------|
| `language/plot-dialect`     | hashicorp/random     | **plot** dialect — declare-authored `*.tfplot.hcl` + `config_promote` |
| `language/local-module`     | hashicorp/random     | a **plot** calling `./modules/greeting` by a portable relative `source` |
| `language/turf-actions`     | hashicorp/tfcoremock | Turf-native `turf_confirm` + `turf_action` gates (no provider)     |

## Use cases

The `use-cases/` tree holds end-to-end stacks for a particular domain: a **tofu**
configuration that composes several local modules under `modules/`, rather than a
single-idea example. Drive them the same way (`turf -C <dir> up`).

| Example                  | Providers                                | Local? | Notes                                                        |
|--------------------------|------------------------------------------|--------|--------------------------------------------------------------|
| `datacenter/ngc-stack`   | tehcyx/kind, hashicorp/helm (v3+), hashicorp/null | ✅ | NVIDIA NGC operators on a GPU-less cluster — four charts, four modules, zero credentials |
| `datacenter/aicr-stack`  | tehcyx/kind, hashicorp/helm (v3+), hashicorp/null | ✅ | The same idea generated rather than written — 16 releases, 18 `depends_on` edges, from one NVIDIA AICR recipe |

The NGC stack is worth reading for what it proves about NVIDIA's operators: the
GPU Operator and the NIM Operator both install and reach a healthy state with no
NVIDIA GPU and **no NGC API key**, and both then wait on the same Node Feature
Discovery label (`feature.node.kubernetes.io/pci-10de.present`). Only NIM *model*
content needs a credential. See
[`use-cases/datacenter/ngc-stack/README.md`](use-cases/datacenter/ngc-stack/README.md).

The AICR stack is the same subject one order of magnitude up, and nothing in it
was written by hand: a recipe from [NVIDIA AI Cluster Runtime](https://github.com/NVIDIA/aicr)
is generated into sixteen module calls whose `depends_on` edges are the recipe's
own `dependencyRefs`. AICR is explicit that it does not provision clusters, so
every renderer it ships treats the cluster as a precondition — and of those
renderers only Flux carries the full graph; Argo CD and Helmfile flatten it to
barriers. Terraform is the one consumer that can hold the graph *and* create the
cluster underneath it. See
[`use-cases/datacenter/aicr-stack/README.md`](use-cases/datacenter/aicr-stack/README.md).

## Integrations

### `integrations/kagent/` — Kubernetes deployment via kagent

Manifests for deploying the Turf MCP server and an infrastructure agent in-cluster
via the [kagent](https://github.com/kagent-dev/kagent) operator:

| File                      | Purpose                                                              |
|---------------------------|---------------------------------------------------------------------|
| `turf-mcpserver.yaml`     | `MCPServer` — runs `turf-mcp-server` (HTTP) with provider/state PVCs |
| `turf-agent.yaml`         | `Agent` — the infrastructure agent (system prompt, tools, A2A skills)|
| `turf-rbac.yaml`          | `ClusterRoleBinding` (cluster-admin, for the Kubernetes state backend)|
| `turf-pvc.yaml`           | `PersistentVolumeClaim` for caching provider binaries               |
| `turf-model-config.yaml`  | Model provider configuration                                        |
| `opentofu-mcpserver.yaml` | Companion OpenTofu registry `RemoteMCPServer` (provider/module docs)|

```sh
kubectl apply -f integrations/kagent/
```

The container image is built in the [Turf repository](https://github.com/turfbuild/turf)
(`make docker-build`).

### `integrations/turf-cli/` — Turf CLI skill discovery

The standalone [Turf CLI](https://github.com/turfbuild/turf) discovers user skills
from turf-owned locations only — the working dir's `.turf/skills/` and the global
`~/.turf/skills/`. Run the CLI from this directory and it gains a `tagging-policy`
skill (loadable with `read_skill`) on top of the server's built-in `skill_*`
workflows. See `integrations/turf-cli/README.md`.

### `integrations/kubernetes-backend/` — Kubernetes state backend

An HCL config that swaps `backend "local"` for `backend "kubernetes"`, so Turf
persists its state in a cluster Secret (`tfstate-<workspace>-demo`) with locking via
a Coordination Lease, rather than a local file. Backend auth comes from the
environment (`KUBE_CONFIG_PATH`, `KUBE_IN_CLUSTER_CONFIG`), independent of the
`kubernetes` provider's own auth. Needs an existing cluster and a `turf-state`
namespace. For the in-cluster (turf-in-a-pod) RBAC that this backend requires when
Turf runs *inside* the cluster, see `integrations/kagent/`. See
`integrations/kubernetes-backend/README.md`.

### `integrations/scalr/` — Turf tailored for Scalr

Turf as the engine, [Scalr](https://scalr.io) as the control plane: Turf plans and
applies locally while Scalr holds the variables and enforces policy. A `setup/` config
provisions the Scalr side as code with the `scalr` provider (environment, a
**state-storage-only** workspace, a `region` variable, a published registry module, and
an OPA `scalr_policy_group` sourced from this repo). The headline demo, `chat/`,
**composes Scalr's normally remote-only features in a local session**: via a
`turf.yaml` `mcps:` overlay the agent talks to the Scalr and OPA MCP servers, pulling
the workspace variable into the registry module and gating plan-approval on the OPA
policy — governance in the local loop, not a remote run. A `scalr` skill under `.turf/`
teaches the Turf agent these conventions. See `integrations/scalr/README.md`.

## License

Mozilla Public License 2.0. See [LICENSE](./LICENSE).
