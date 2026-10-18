# turf-examples

Reference Terraform/HCL examples and agent integrations for
[Turf](https://github.com/turfbuild/turf) — a drop-in replacement for Terraform
with agentic superpowers, exposed as an infrastructure MCP server.

Every artifact here consumes the Turf MCP server only through the MCP protocol or
through ordinary Terraform HCL — there are no Go imports of Turf internals.

## Layout

```
terraform/        Standard Terraform/HCL configurations
  kubernetes/
    kind-crd/       kind cluster → CustomResourceDefinition → custom resource
    kind-helm/      kind cluster → Helm release (podinfo)
    hpa-walkthrough/  php-apache + HorizontalPodAutoscaler on an existing cluster
    node-maintenance/  a set of nodes held in maintenance, the runbook's steps
                    as actions (kubectl + kubewait + the agent)
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

use-cases/        End-to-end stacks for a real domain, composed from local modules
  datacenter/
    ngc-stack/      NVIDIA GPU Cloud — GPU Operator + NIM Operator + cert-manager
                    + ExternalDNS on a kind cluster with no GPU
    aicr-stack/     NVIDIA AI Cluster Runtime — 16 Helm releases generated from
                    one AICR recipe, deployed as the dependency graph it declares
    aicr-eks-certification/  spec: EKS (ported from mchmarny/cluster) + the AICR
                    stack + an NVCRE certification, waits as Terraform actions
    ansible-k3s/    EC2 hosts made a k3s cluster by an Ansible playbook action,
                    then a CRD and an object of its kind on that cluster
    slinky-stack/   NVIDIA's Slurm-in-Run:ai tutorial as one graph: Slinky + KAI
                    Scheduler + GPU Operator on kind, waits as kubewait actions

integrations/     How to drive turf-mcp-server from different agent runtimes
  kagent/             Kubernetes manifests: MCPServer, Agent, RBAC, PVC, ModelConfig
  turf-cli/           Configuring the standalone Turf CLI (.turf/): user skills
                      + model config (turf.yaml — first-available, named, local)
  kubernetes-backend/ Store Turf state in-cluster via the kubernetes state backend
  scalr/              Turf tailored for Scalr: remote backend, setup-as-code,
                      OPA policy, module registry, and MCP read-back
```

## Running the examples

Every example runs the same way. Turf plans and applies through an engine that runs
on your machine as a Homebrew service, so a rollout keeps going when the client or
the conversation that started it ends.

**Install Turf and start its service:**

```bash
brew install restatedev/tap/restate-server turfbuild/tap/turf
brew services start turf    # starts the engine now and at every login
```

**Connect your agent.** One command registers the server with the agents on your machine
— Claude Code, Claude Desktop, Cursor, Codex, Gemini CLI, VS Code — and writes each config
with the server's absolute path (Node 18+; the agent's own command does the same, e.g.
`claude mcp add turf --scope user -- turf-mcp-server`). In Claude Code and Claude Desktop,
Turf runs on your Claude subscription, no model API key.

```bash
npx add-mcp@2 "$(command -v turf-mcp-server)" --name turf -g
```

**Run an example** from your agent — in Claude Code, opened at this repo's root — or from the
Turf CLI, which brings its own model and needs an API key:

```
/turf:up terraform/kubernetes/kind-crd    # Claude Code
turf -C terraform/kubernetes/kind-crd up        # the Turf CLI
```

The MCP tools are Terraform's commands. `init` registers an example's directory and
installs its modules and providers, `open` binds its state, and `up` plans
the first **round**. Each round stops at its approval point with its plan as a resource
(`plan.uri`, OpenTofu's JSON plan, exactly as `tofu show -json` prints it; `show` reads it).
`apply` with that plan's `plan.digest` approves it: it applies the round, plans the
next, and stops again, until the configuration has converged. Not calling `apply`
declines the plan. `destroy` tears down the same way. A value known only after an
apply, such as a new cluster's endpoint, defers whatever reads it to the next round.
That is how several examples here go from nothing to a running stack in one `up`.

**A remote engine.** `TURF_RESTATE_URL` points the CLI or the server at an engine
running elsewhere, such as in a cluster ([`integrations/kagent/`](integrations/kagent/)),
instead of the local service.

**What the providers see.** Provider plugins run inside the engine, not in your shell,
so they get the service's environment: launchd's, with Homebrew's `PATH`, plus what
`~/.homebrew/services/turf.env` sets (`KEY=value` lines; run `brew services restart turf`
after editing it). When [mise](https://mise.jdx.dev) is installed, each configuration's
providers also get that configuration's mise environment: what `mise env` prints in its
directory, from a committed `mise.toml` and an untracked `mise.local.toml` beside it.
Run `mise trust` in the directory once. `TURF_MISE=off` in `turf.env` turns this off.

- **Credentials** for providers come from files (the default profile in
  `~/.aws/config`, `~/.kube/config`, gcloud's application-default credentials, the
  `az` login), from provider arguments in the HCL (`profile`, `config_path`), or from
  the configuration's `mise.local.toml`. Anything that is yours rather than the
  configuration's goes in `turf.env`.
- **The state backend's credentials and `TF_VAR_*` variables** come from the session:
  the environment you started the CLI or the MCP client in.

Each example's README says what else it needs.

## Terraform examples

Each `terraform/<...>` directory is a self-contained, ordinary Terraform configuration —
plain `.tf` files. Drive it from your agent (`/turf:up <dir>` in Claude Code, or the
MCP tools: `init` against the directory, then `up`) or with the Turf CLI (`turf -C <dir> up`),
as [Running the examples](#running-the-examples) describes. See each example's
`README.md` for prerequisites, usage, and cleanup. An example may carry a
`*.turf.hcl` file beside its `.tf`: Turf actions — steps the agent driving Turf
performs, a check, a notice or a question for the user — that tofu and terraform
ignore and Turf lays over the configuration at every plan.

| Example                        | Providers                     | Local? | Notes                                              |
|--------------------------------|-------------------------------|--------|----------------------------------------------------|
| `kubernetes/kind-crd`          | tehcyx/kind, hashicorp/kubernetes | ✅ | CRD-then-CR convergence in one run                 |
| `kubernetes/kind-helm`         | tehcyx/kind, hashicorp/helm (v3+) | ✅ | Helm release on a local kind cluster               |
| `kubernetes/hpa-walkthrough`   | hashicorp/kubernetes          | ⎈ | HPA walkthrough — `ignore_changes` on replicas     |
| `kubernetes/node-maintenance`  | hashicorp/kubernetes, hashicorp/local, turfbuild/kubewait | ⎈ | nodes in maintenance as a set, every step of the runbook an action — cordon, drain, confirm, repair, re-certify, uncordon; Terraform 1.16+ runs the kubectl half, Turf the whole runbook |
| `aws/lambda-fleet`             | hashicorp/aws, hashicorp/archive | ☁️ AWS | fleet of Lambdas patched in place (`count`)        |
| `azure/avm-resourcegroup`      | hashicorp/azurerm + AVM module | ☁️ Azure | multi-instance keyed modules (`for_each`/`count`) |
| `gcp/gke-demo`                 | hashicorp/google              | ☁️ GCP | GKE Autopilot + custom VPC                         |
| `language/actions`             | hashicorp/tfcoremock, hashicorp/local | ✅ | Terraform Actions (gating invokes)          |
| `language/two-phase`           | hashicorp/tfcoremock          | ✅ | staged-then-commit via actions (advanced)          |
| `language/replace-ordering`    | hashicorp/random              | ✅ | replace teardown ordering + infectious CBD         |
| `language/environments`        | hashicorp/random, hashicorp/tfcoremock | ✅ | one configuration, a workspace per environment, promotion with a gate |
| `modules/podinfo`              | hashicorp/helm (v3+)          | — | podinfo as a child module, to call at a pinned ref  |

✅ = credential-free / local. ☁️ = needs a cloud account. ⎈ = needs an existing
Kubernetes cluster + kubeconfig.

## Use cases

The `use-cases/` tree holds end-to-end stacks for a particular domain: an ordinary
Terraform configuration that composes several local modules under `modules/`, rather
than a single-idea example. Drive them the same way (`/turf:up <dir>`, or `turf -C <dir> up`).

| Example                  | Providers                                | Local? | Notes                                                        |
|--------------------------|------------------------------------------|--------|--------------------------------------------------------------|
| `datacenter/ngc-stack`   | tehcyx/kind, hashicorp/helm (v3+), hashicorp/null | ✅ | NVIDIA NGC operators on a GPU-less cluster — four charts, four modules, zero credentials |
| `datacenter/aicr-stack`  | tehcyx/kind, hashicorp/helm (v3+), built-in `terraform_data` | ✅ | The same idea generated rather than written — 16 releases, 18 `depends_on` edges, from one NVIDIA AICR recipe |
| `datacenter/aicr-eks-certification` | hashicorp/aws, hashicorp/kubernetes, hashicorp/helm (v3+) | 📐 | Target-state spec: a real GPU cluster, its stack and its NVCRE certification as one graph; the waits are a specified action |
| `datacenter/ansible-k3s` | hashicorp/aws, ansible/ansible, hashicorp/kubernetes | ☁️ AWS | Hosts by Terraform, k3s by Ansible, a custom resource by Terraform again — one graph, three rounds on Turf |
| `datacenter/slinky-stack` | tehcyx/kind, hashicorp/helm (v3+), turfbuild/kubewait | ✅ | A Slurm cluster in a "Run:ai project" with KAI Scheduler as the open Run:ai — `srun` works, the GPU partition pends; two rounds on Turf |
| `products/data-lake-installer` | hashicorp/aws | ✅ plan | A product's installer: a data lake reference architecture that plans with no credentials, with the installer's own steps as Turf actions |
| `guardrails`             | tehcyx/kind, hashicorp/helm (v3+), hashicorp/random | ✅ | Scan every provider before it runs, pin the workload to a commit, check every plan against policy — and make two of those a step of the apply |

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

The Ansible k3s stack is the datacenter cascade with every hand-off inside the
graph: the inventory is a value built from the hosts' outputs, one
`ansible_playbook_run` action installs k3s across them, the playbook fetches the
kubeconfig back to a file that a data source reads, and the `kubernetes`
provider is configured from it. Teardown runs back through the same seam, with
the cluster objects deleted through its API before the hosts and the network.
Turf converges it in one command; plain Terraform needs targeted applies. See
[`use-cases/datacenter/ansible-k3s/README.md`](use-cases/datacenter/ansible-k3s/README.md).

The Slinky stack is NVIDIA's Run:ai tutorial for Slurm, eight imperative steps
across helm, kubectl and the `runai` CLI, as one configuration on a GPU-less kind
cluster: cert-manager, the GPU Operator, KAI Scheduler (the scheduler inside
Run:ai, open-sourced) with the Run:ai project written as a queue, SchedMD's
Slinky operator, and a Slurm cluster whose pods KAI schedules. The tutorial's
`kubectl patch` of a Helm-owned object becomes values. Two releases have nothing
for helm's wait to wait on, KAI because it is operator-shaped and Slurm because
its chart renders only custom resources, so the waits that mean something are
`kubewait_condition` actions: on KAI's own readiness, on Slurm's own count of
IDLE nodes, and on the pods draining before the operator goes. `srun -N2` runs
across both workers; `srun --gres=gpu:1` gets the tutorial's own rejection. See
[`use-cases/datacenter/slinky-stack/README.md`](use-cases/datacenter/slinky-stack/README.md).

📐 = a **spec**: it validates and its mocked `terraform test` suite passes, but
it has never run end to end. Turf supports what it uses except forwarding
`timeouts {}`, which is not verified, and nothing in it has run against a real
cluster. The EKS certification example is one. It takes the Terraform AICR's own UAT uses for
EKS test clusters (ported from `mchmarny/cluster`), the same AICR stack, and an
NVCRE certification of the GPU pools, and writes them as one configuration.
The waits that live in CI shell today become a Terraform action
(`kubewait_condition`, specified in the example), and teardown is the graph in
reverse. See
[`use-cases/datacenter/aicr-eks-certification/README.md`](use-cases/datacenter/aicr-eks-certification/README.md).

## Integrations

### `integrations/kagent/` — Kubernetes deployment via kagent

Manifests for deploying Turf and an infrastructure agent in-cluster via the
[kagent](https://github.com/kagent-dev/kagent) operator. In a cluster Turf runs as
three parts, each in its own pod: the MCP server the agent talks to, the engine that
plans and applies (and runs the provider plugins), and the restate-server the engine
runs on. The server finds the engine through `TURF_RESTATE_URL`.

| File                      | Purpose                                                              |
|---------------------------|---------------------------------------------------------------------|
| `turf-mcpserver.yaml`     | `MCPServer` — runs `turf-mcp-server` (HTTP), pointed at the engine with `TURF_RESTATE_URL` |
| `turf-engine.yaml`        | `Deployment` + `Service` — `turf-engine`, from the same image, registered with restate-server |
| `restate.yaml`            | `StatefulSet` + `Service` — restate-server from Restate's own image, its data on a volume |
| `turf-agent.yaml`         | `Agent` — the infrastructure agent (system prompt, tools, A2A skills)|
| `turf-rbac.yaml`          | `ClusterRoleBinding` (cluster-admin, for the Kubernetes state backend and in-cluster providers)|
| `turf-pvc.yaml`           | `PersistentVolumeClaim` the server and the engine share: configurations, plans, the provider cache |
| `turf-model-config.yaml`  | Model provider configuration                                        |
| `opentofu-mcpserver.yaml` | Companion OpenTofu registry `RemoteMCPServer` (provider/module docs)|
| `networkpolicy.yaml`      | `NetworkPolicy` — who may reach restate-server, the engine and the MCP server |

The engine reads each configuration directory itself, so the server and the engine
mount one volume at the same path. Provider credentials belong on the engine, where
the plugins run; the state backend's belong on the server.

The kagent agent has no file tools, so it **operates** existing configurations — plan,
apply, destroy, import, and actions — but does not author them; writing `.tf` needs a
client with file tools (the Turf CLI, Claude Code).

**Who can reach Turf.** restate-server has no authentication of its own, and neither
does the MCP server's HTTP transport, so the stack is closed by two things:

- **Request identity.** restate-server signs every request it sends the engine, and
  the engine serves nothing else. The key lives in a Secret both pods need, so create
  it once **before** `kubectl apply` (until it exists, neither starts). The engine,
  from the same image, makes the key and prints its public half:

  ```sh
  docker run --rm --user "$(id -u)" -v "$PWD:/k" ghcr.io/turfbuild/turf-mcp-server:<release> \
    turf-engine --identity-keygen /k/identity.pem > public-key
  kubectl -n kagent create secret generic turf-engine-identity \
    --from-file=identity.pem --from-file=public-key
  rm identity.pem
  ```

  restate-server mounts `identity.pem`; the engine is given only `public-key`. The
  engine checks signatures from the first Turf release after v0.18.0, and
  `--identity-keygen` arrives with it: an older image accepts the Secret and ignores
  it, leaving the network policy below as the only control.
- **`networkpolicy.yaml`**: restate-server's ingress only from the MCP server, its
  admin API only from the engine, the engine only from restate-server, and the MCP
  server only from the agent and kagent's controller. Policies are enforced by the
  cluster's network plugin — on AKS, a network policy engine chosen when the cluster
  is created (`--network-policy azure|calico|cilium`); Calico and Cilium elsewhere, and
  kind's own plugin (kind v0.32) — and a plugin that does not enforce them accepts them
  silently, so check with a throwaway pod that restate's ports time out:

  ```sh
  kubectl -n kagent run probe --rm -i --restart=Never --image=curlimages/curl -- \
    curl -sS --max-time 5 http://restate.kagent.svc:8080/restate/health   # must time out
  ```

  `kubectl port-forward` still reaches restate's admin API for an operator: it enters
  the pod through the kubelet.

```sh
kubectl apply -f integrations/kagent/
```

The container image is published with each Turf release as
`ghcr.io/turfbuild/turf-mcp-server:<release>`; it carries both the server and
`turf-engine`. Keep the server's and the engine's tags equal.

### `integrations/turf-cli/` — Turf CLI skill discovery

The standalone [Turf CLI](https://github.com/turfbuild/turf) discovers user skills
from turf-owned locations only — the working dir's `.turf/skills/` and the global
`~/.turf/skills/`. Run the CLI from this directory and it gains a `tagging-policy`
skill, loaded on demand like the server's built-in `skill_*` workflows. See
`integrations/turf-cli/README.md`.

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
