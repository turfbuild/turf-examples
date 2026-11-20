# An AICR recipe on a cluster that already exists

[`../aicr-stack`](../aicr-stack/README.md) creates a kind cluster and fills it with an
[NVIDIA AI Cluster Runtime](https://github.com/NVIDIA/aicr) recipe in one configuration. This
is the other half of that story, and the shape a management cluster runs: the workload cluster
is somebody else's to provision, and the runtime is installed on it from outside, by name.

Nothing here is new Terraform. The module call is `../aicr-stack/bundle`, the same generated
bundle, with the same graph: 17 Helm releases for the recipe's 14 components, four levels deep.
This directory adds the helm provider, the cluster's name, and one question for a person.

```hcl
module "stack" {
  source          = "../aicr-stack/bundle"
  cluster_keepers = var.cluster_name
}
```

## Where the cluster's credentials are

The helm provider reads a kubeconfig file where Turf's engine runs,
`<clusters_dir>/<cluster_name>.kubeconfig` (`/turf/clusters` by default), and nowhere else: it
is not in this configuration, not in the state, and not with whoever asks for the plan. In a
management cluster that directory is a Secret mounted into the engine's pods, one key per
workload cluster, so giving the engine another cluster is adding a key.
[turfbuild/turf-kagent](https://github.com/turfbuild/turf-kagent) runs it that way, with an
agent in kagent asking for the plan and a person approving it.

On a laptop, point it at any kubeconfig:

```sh
turf -C use-cases/datacenter/aicr-workload-cluster up \
  -var cluster_name=aicr-1 -var kubeconfig=$HOME/.kube/aicr-1.kubeconfig
```

It declares no backend and commits its lock file, so it runs from the
[examples image](../../../README.md#configuration-images): whoever opens a workspace names the
backend.

| Variable | Default | Purpose |
| --- | --- | --- |
| `cluster_name` | (required) | The workload cluster; also the containment keeper, so pointing the stack at another cluster replaces every release there |
| `clusters_dir` | `/turf/clusters` | Where the engine keeps `<cluster_name>.kubeconfig` |
| `kubeconfig` | (none) | A kubeconfig path, overriding `clusters_dir` |

## The apply stops and asks

`window.turf.hcl` binds a turf action `before_create` to the GPU Operator's release. The apply
installs everything the operator depends on, then stops at `awaiting_actions` with the prompt:
ask the user whether the cluster's maintenance window is open. On real nodes that release is
the one that touches every GPU host (driver, container toolkit, device plugin), so it is the
one a person schedules.

```hcl
action_trigger "maintenance_window" {
  target     = module.stack.module.gpu_operator.helm_release.this
  events     = [before_create]
  actions    = [action.turf_action.maintenance_window]
  on_failure = halt
}
```

The agent driving Turf asks, and answers with the person's own words. A yes lets the operator
and the last level of the graph install. A no halts the round with their reason: what is
installed stays, and the next `up` plans the rest.

A second action, `handover`, is bound to no event: run it with `invoke` when the cluster is
ready to leave your hands.

## What a run looks like

Measured on Turf 1.4.0 from an engine in another cluster, against a single-node kind cluster
with no GPU and the images already on the node:

```
plan      31 to add                                         (17 helm_release, 14 terraform_data)
apply     levels 0 and 1                                    about 2 min 15 s, then the question
answer    yes
apply     gpu-operator, its readiness check, the last level about 1 min 25 s, converged
destroy   31 to destroy                                     about 45 s
```

With no GPU the GPU Operator lands idle (`ClusterPolicy ready, NoGPUNodes`), as in `aicr-stack`.
The stack installs again on the same cluster after a destroy.
