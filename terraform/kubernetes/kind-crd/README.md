# CRD and custom resource on a kind cluster

Spin up a local Kubernetes cluster with [`kind`](https://kind.sigs.k8s.io/), register
a `CustomResourceDefinition`, and create an instance of it — all locally, no cloud
account or credentials.

## Demo

[![turf up converging a kind cluster, a CRD, and a custom resource in one run](https://turf.build/demos/kind-crd-up-poster.png)](https://turf.build/demo/)

▶ **[Watch the full walkthrough at turf.build/demo](https://turf.build/demo/)** — `turf up` converges
the cluster, the CRD, and the custom resource in one governed run; `turf destroy` tears it down in
reverse order.

<!-- Prefer an inline, autoplaying video in this README instead of the poster above? Edit this file
     on github.com and drag recordings/out/kind-crd-up.mp4 (from the internal headquarters repo)
     into the editor; GitHub mints a https://github.com/user-attachments/assets/… URL. Replace the
     image+link above with:
       <video src="PASTE-THE-URL" controls muted playsinline width="100%"></video> -->


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

## Replacing the cluster

Roll the cluster and everything on it, with **no gap in service**:

```bash
turf -C terraform/kubernetes/kind-crd up --var generation=2
```

The new cluster comes up alongside the old one, the CRD and custom resource are created
on it, and only then are the old ones removed and the old cluster torn down. For about a
minute both clusters are running and the old custom resource is still being served:

```
kind get clusters
turf-crd-demo-1      ← still serving
turf-crd-demo-2      ← coming up
```

Both manifests declare two things that make this work:

```hcl
lifecycle {
  create_before_destroy = true
  replace_triggered_by  = [kind_cluster.demo.endpoint]
}
```

`replace_triggered_by` says the object lives *inside* the cluster. Without it, replacing
the cluster destroys the CRD and the custom resource as a side effect of the container
going away — no provider RPC, no `delete` in the plan, no chance to run a finalizer — and
their state entries survive pointing at objects that no longer exist. Turf reports the
replacement as `replace_by_triggers`, so an approver reading a replacement they did not
ask for can see what it followed from.

`create_before_destroy` says the old objects must keep serving until the new ones exist.
It is also why the cluster's name carries `var.generation`: two kind clusters cannot share
a name, so the old and new generations need different ones to coexist. The cluster itself
declares no lifecycle block — Turf forces create-before-destroy onto it because the things
it contains asked for it.

The old objects are then removed in reverse dependency, so the custom resource goes before
the CRD that defines its kind — the order you would use by hand.

Two more things worth knowing:

- **Containment has to be declared** — the graph cannot infer it. A provider whose
  configuration *references* a resource does not necessarily manage objects that live
  *inside* it (`provider "aws" { assume_role { role_arn = aws_iam_role.deployer.arn } }`
  is the counterexample: replace that role and nothing ceases to exist).
- **Reference `.endpoint`, not the bare resource.** A whole-resource reference fires on
  any update to the cluster, so an unrelated attribute change would tear down the
  cluster's contents for nothing.

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

The cluster's context is `kind-<cluster_name>`, and `cluster_name` is an output — it
carries the generation suffix, so it is `kind-turf-crd-demo-1` unless you changed
`generation`:

```bash
CTX=kind-$(turf -C terraform/kubernetes/kind-crd output -raw cluster_name)
kubectl --context $CTX get crd turfs.demo.local
kubectl --context $CTX get turf example-turf -o yaml
```

## Cleanup

```bash
turf -C terraform/kubernetes/kind-crd destroy
kind delete cluster --name turf-crd-demo-1   # if anything is left behind
```
