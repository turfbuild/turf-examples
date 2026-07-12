# CRD and custom resource on a kind cluster

Spin up a local Kubernetes cluster with [`kind`](https://kind.sigs.k8s.io/), register
a `CustomResourceDefinition`, and create an instance of it — all locally, no cloud
account or credentials.

## What This Demonstrates

This is the clearest showcase of **Turf's cross-phase convergence**. Three things must
happen in order, and each depends on the previous one existing:

1. The **cluster** is created — its API endpoint and certificates are computed.
2. The **CRD** registers a new API kind (`demo.local/v1` `Turf`).
3. The **custom resource** — an instance of that kind — can only be planned once the
   CRD is live, because the kind doesn't exist in the cluster's API until then.

The kubernetes provider's connection is unknown until the cluster exists, and the CR's
kind is unknown until the CRD is applied. Turf converges all three in a single run: it
defers the provider config and the CR, applies the cluster then the CRD, reloads the
provider so it re-discovers the new API, and finishes the CR — no manual targeting.

## Resources Created

- `kind_cluster.demo` — a local Kubernetes cluster running as Docker containers.
- `kubernetes_manifest.crd` — a `Turf` CustomResourceDefinition (`demo.local/v1`).
- `kubernetes_manifest.instance` — a `Turf` custom resource with a `spec.message`.

## Prerequisites

- Docker (kind runs the cluster as containers)
- `kind` and `kubectl` on your PATH
- The Turf CLI, or any MCP client pointed at `turf-mcp-server`

## Usage

```bash
turf -C terraform/kubernetes/kind-crd up
```

## Verify

```bash
kubectl --context kind-turf-crd-demo get crd turfs.demo.local
kubectl --context kind-turf-crd-demo get turf example-turf -o yaml
```

## Cleanup

```bash
turf -C terraform/kubernetes/kind-crd destroy
kind delete cluster --name turf-crd-demo   # if anything is left behind
```
