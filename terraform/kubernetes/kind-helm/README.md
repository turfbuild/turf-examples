# Helm release on a kind cluster

Spin up a local Kubernetes cluster with [`kind`](https://kind.sigs.k8s.io/) and
install a Helm chart onto it — entirely locally, no cloud account or credentials.

## What This Demonstrates

The Helm provider is configured from the kind cluster's **computed** connection
details (`endpoint`, client certs). Those values don't exist until the cluster is
created, so the `helm_release` can't be planned up front. Turf converges it in a
single run: it defers the release to a later phase, applies the cluster, then
re-plans the release against the now-known connection.

## Replacing the cluster

The release declares what its replacement follows from:

```hcl
lifecycle {
  replace_triggered_by = [kind_cluster.demo.endpoint]
}
```

Without it, replacing the cluster destroys the release as a side effect of the
containers going away — helm never runs its uninstall, no hooks fire, nothing appears
in the plan — and the state entry survives pointing at a release that no longer
exists. With it, replacing the cluster plans the graceful sequence instead:

```
delete helm_release.podinfo   (uninstalled through the OLD cluster's endpoint)
destroy kind_cluster.demo
create  kind_cluster.demo
… next phase: install podinfo again
```

Turf reports the forced replacement as `replace_by_triggers`, so an approver reading a
replacement they did not ask for can see what it followed from.

Two things are worth knowing about the declaration:

- **It has to be declared** — the graph cannot infer it. A provider whose configuration
  *references* a resource does not necessarily manage objects that live *inside* it
  (`provider "aws" { assume_role { role_arn = aws_iam_role.deployer.arn } }` is the
  counterexample: replace that role and nothing ceases to exist).
- **Reference `.endpoint`, not the bare resource.** A whole-resource reference fires on
  any update to the cluster, so an unrelated attribute change would uninstall and
  reinstall the release for nothing.

Try it with `plan_new(replace: ["kind_cluster.demo"])`.

## Resources Created

- `kind_cluster.demo` — a local Kubernetes cluster running as Docker containers.
- `helm_release.podinfo` — the [podinfo](https://github.com/stefanprodan/podinfo)
  demo chart, installed into its own namespace.

## Prerequisites

- Docker (kind runs the cluster as containers)
- `kind` and `kubectl` on your PATH
- The Turf CLI, or any MCP client pointed at `turf-mcp-server`

## Usage

```bash
turf -C terraform/kubernetes/kind-helm up
```

Turf plans, defers the release, applies the cluster, and re-converges — one command.

## Verify

```bash
kubectl --context kind-turf-helm-demo -n podinfo get pods
kubectl --context kind-turf-helm-demo -n podinfo port-forward svc/podinfo 9898:9898
# then open http://localhost:9898
```

## Cleanup

```bash
turf -C terraform/kubernetes/kind-helm destroy
kind delete cluster --name turf-helm-demo   # if anything is left behind
```

## Why podinfo (and not bitnami/nginx)

Bitnami sunset its public catalog on 2025-08-28 (images moved to
`docker.io/bitnamilegacy`), so bitnami charts now leave pods in `ImagePullBackOff`
and helm's `wait` times out. podinfo's image lives on ghcr.io and pulls cleanly,
so the release converges in seconds.

## Notes on the Helm provider

This example uses **helm provider v3+**, where the cluster connection is a nested
*attribute* — `kubernetes = { host = ..., client_certificate = ..., ... }` — rather
than the v2 `kubernetes { ... }` block. See `providers.tf`.
