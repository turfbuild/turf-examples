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

Roll the cluster and everything on it, with **no gap in service**:

```bash
turf -C terraform/kubernetes/kind-helm up --var generation=2
```

The new cluster comes up alongside the old one, podinfo is installed on it and waits
until its pods are Ready, and only then is the old release uninstalled and the old
cluster torn down. For about a minute both clusters are running and the old podinfo is
still answering:

```
kind get clusters
turf-helm-demo-1      ← still serving
turf-helm-demo-2      ← coming up
```

The release declares two things that make this work:

```hcl
lifecycle {
  create_before_destroy = true
  replace_triggered_by  = [kind_cluster.demo.endpoint]
}
```

`replace_triggered_by` says the release lives *inside* the cluster. Without it, replacing
the cluster destroys the release as a side effect of the containers going away — helm
never runs its uninstall, no hooks fire, nothing appears in the plan — and the state entry
survives pointing at a release that no longer exists. Turf reports the replacement as
`replace_by_triggers`, so an approver reading a replacement they did not ask for can see
what it followed from.

`create_before_destroy` says the old release must keep serving until the new one is up.
It is also why the cluster's name carries `var.generation`: two kind clusters cannot share
a name, so the old and new generations need different ones to coexist. The cluster itself
declares no lifecycle block — Turf forces create-before-destroy onto it because the thing
it contains asked for it.

Two more things worth knowing:

- **Containment has to be declared** — the graph cannot infer it. A provider whose
  configuration *references* a resource does not necessarily manage objects that live
  *inside* it (`provider "aws" { assume_role { role_arn = aws_iam_role.deployer.arn } }`
  is the counterexample: replace that role and nothing ceases to exist).
- **Reference `.endpoint`, not the bare resource.** A whole-resource reference fires on
  any update to the cluster, so an unrelated attribute change would uninstall and
  reinstall the release for nothing.

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

The cluster's context is `kind-<cluster_name>`, and `cluster_name` is an output — it
carries the generation suffix, so it is `kind-turf-helm-demo-1` unless you changed
`generation`:

```bash
CTX=kind-$(turf -C terraform/kubernetes/kind-helm output -raw cluster_name)
kubectl --context $CTX -n podinfo get pods
kubectl --context $CTX -n podinfo port-forward svc/podinfo 9898:9898
# then open http://localhost:9898
```

## Cleanup

```bash
turf -C terraform/kubernetes/kind-helm destroy
kind delete cluster --name turf-helm-demo-1   # if anything is left behind
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
