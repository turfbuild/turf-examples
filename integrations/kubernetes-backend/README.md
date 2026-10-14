# Kubernetes state backend

Store Turf/OpenTofu state **in the Kubernetes cluster itself** instead of a local
file — state lives in a Secret, with locking via a Coordination Lease. A trivial
namespace + ConfigMap workload rides along so there's something to persist.

## What This Demonstrates

`providers.tf` swaps the usual `backend "local"` for `backend "kubernetes"`:

```hcl
backend "kubernetes" {
  secret_suffix = "demo"
  namespace     = "turf-state"
}
```

- **State** is written to a Secret named `tfstate-<workspace>-demo` (so
  `tfstate-default-demo` for the default workspace) in the `turf-state` namespace.
- **Locking** uses a Coordination Lease alongside it, so concurrent runs can't
  clobber each other.
- **Auth is out-of-band.** Backend blocks can't reference HCL variables, so the
  backend authenticates from the session's environment (the shell you start the
  Turf CLI or MCP client from) — `KUBE_CONFIG_PATH`, `KUBE_IN_CLUSTER_CONFIG`,
  `KUBE_CONFIG_PATHS`, etc. — or from `open`'s `backend_config`, Turf's
  `tofu init -backend-config=...`. This is independent of how the
  `kubernetes` *provider* authenticates (which does use variables, here
  `kubeconfig_path` / `kubeconfig_context`).

The state backend and the resource provider are two separate concerns pointed at the
same cluster.

## Prerequisites

- A Kubernetes cluster and a kubeconfig.
- The state namespace must exist before the first run:
  ```bash
  kubectl create namespace turf-state
  ```
- The Turf CLI, or any MCP client pointed at `turf-mcp-server`.

## Usage

```bash
export KUBE_CONFIG_PATH="$HOME/.kube/config"   # backend auth
turf -C integrations/kubernetes-backend up
```

## Verify

```bash
kubectl -n turf-state get secret,lease
# secret/tfstate-default-demo   … the state
# lease/lock-tfstate-default-demo … the lock
```

The lock is held while a session follows a convergence, including one paused at its
approval point, as `tofu apply` holds it at its prompt. It is released when the
convergence ends, or when the session lets go of it: `close`, the server
exiting, or a pause longer than a day. The convergence itself waits in the engine,
and the next `apply` takes the lock again.

## Cleanup

```bash
turf -C integrations/kubernetes-backend destroy
```

`destroy` removes the workload but leaves the state Secret/Lease (they track an
now-empty state). Delete them — and the namespace — to fully reset:

```bash
kubectl delete namespace turf-state
```

## Running Turf in-cluster

To run Turf *inside* the cluster, the MCP server's pod uses its ServiceAccount token
for the backend, which needs a Role granting access to `secrets` and `leases`, and
the engine's pod uses its own for the providers it runs. That operational setup —
ServiceAccounts, RBAC, and deployment manifests — lives in
[`integrations/kagent/`](../kagent/) (see `turf-rbac.yaml`), which deploys the Turf
MCP server, its engine and restate-server in-cluster via the kagent operator.
