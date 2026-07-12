# Helm release on a kind cluster

Spin up a local Kubernetes cluster with [`kind`](https://kind.sigs.k8s.io/) and
install a Helm chart onto it — entirely locally, no cloud account or credentials.

## What This Demonstrates

The Helm provider is configured from the kind cluster's **computed** connection
details (`endpoint`, client certs). Those values don't exist until the cluster is
created, so the `helm_release` can't be planned up front. Turf converges it in a
single run: it defers the release to a later phase, applies the cluster, then
re-plans the release against the now-known connection.

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
turf -C terraform/kubernetes/kind-helm
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
