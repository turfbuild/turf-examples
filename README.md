# turf-examples

Reference Terraform/HCL examples and agent integrations for
[Turf](https://github.com/turfbuild/turf) — a drop-in replacement for Terraform
with agentic superpowers, exposed as an infrastructure MCP server.

Every artifact here consumes the Turf MCP server only through the MCP protocol or
through ordinary Terraform HCL — there are no Go imports of Turf internals.

## Layout

```
terraform/        HCL examples, grouped by provider/cloud + a language/ group
  kubernetes/
    kind-crd/       kind cluster → CustomResourceDefinition → custom resource
    kind-helm/      kind cluster → Helm release (podinfo)
    hpa-walkthrough/  php-apache + HorizontalPodAutoscaler on an existing cluster
  azure/
    avm-resourcegroup/   multi-instance Azure resource groups via a published AVM module
  gcp/
    gke-demo/       GKE Autopilot cluster with custom VPC networking
  language/         Terraform/Turf language & feature demos
    actions/        Terraform Actions — action blocks + lifecycle.action_trigger
    turf-actions/   Turf-native actions — turf_confirm (human) + turf_action (agent)
    two-phase/      staged-then-commit convergence (stretch/advanced)
    replace-ordering/  replacement teardown ordering + infectious create-before-destroy
    plot-dialect/   plot units (*.tfplot.hcl) authored by declare_*, then config_promote

integrations/     How to drive turf-mcp-server from different agent runtimes
  kagent/             Kubernetes manifests: MCPServer, Agent, RBAC, PVC, ModelConfig
  turf-cli/           Skill-discovery demo for the standalone Turf CLI (.turf/skills/)
  kubernetes-backend/ Store Turf state in-cluster via the kubernetes state backend
```

## Terraform examples

Each `terraform/<...>` directory is a self-contained configuration that runs from
its own directory. Drive it with the Turf CLI (`turf -C <dir> up`) or the MCP tools
(`config_init` against the directory, then `plan_new` — its initial walk plans the whole tree). See each example's `README.md` for prerequisites, usage, and cleanup.

**Two dialects.** A configuration directory is either a **tofu** configuration (plain
hand-authored `.tf` files — every example below except one) or a **plot** (turf-authored
`*.tfplot.hcl` units, one per address, written by the `declare_*` tools from an ad-hoc
session). `config_init` reports which. `language/plot-dialect` is the plot showcase and
walks through `config_promote`, the one-way graduation of a plot into a tofu configuration.

| Example                        | Providers                     | Local? | Notes                                              |
|--------------------------------|-------------------------------|--------|----------------------------------------------------|
| `kubernetes/kind-crd`          | tehcyx/kind, hashicorp/kubernetes | ✅ | CRD-then-CR convergence in one run                 |
| `kubernetes/kind-helm`         | tehcyx/kind, hashicorp/helm (v3+) | ✅ | Helm release on a local kind cluster               |
| `kubernetes/hpa-walkthrough`   | hashicorp/kubernetes          | ⎈ | HPA walkthrough — `ignore_changes` on replicas     |
| `azure/avm-resourcegroup`      | hashicorp/azurerm + AVM module | ☁️ Azure | multi-instance keyed modules (`for_each`/`count`) |
| `gcp/gke-demo`                 | hashicorp/google              | ☁️ GCP | GKE Autopilot + custom VPC                         |
| `language/actions`             | hashicorp/tfcoremock, hashicorp/local | ✅ | Terraform Actions (gating invokes)          |
| `language/turf-actions`        | hashicorp/tfcoremock          | ✅ | Turf-native `turf_confirm` + `turf_action` gates   |
| `language/two-phase`           | hashicorp/tfcoremock          | ✅ | staged-then-commit via actions (advanced)          |
| `language/replace-ordering`    | hashicorp/random              | ✅ | replace teardown ordering + infectious CBD         |
| `language/plot-dialect`        | hashicorp/random              | ✅ | **plot** dialect — declare-authored `*.tfplot.hcl` + `config_promote` |

✅ = credential-free / local. ☁️ = needs a cloud account. ⎈ = needs an existing
Kubernetes cluster + kubeconfig.

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

## License

Mozilla Public License 2.0. See [LICENSE](./LICENSE).
