# In-cluster greeting

A namespace and a ConfigMap, written through a local module by the Kubernetes
provider using the service account of the pod it runs in. It is small on purpose:
this is the configuration the kagent integration runs, published as a
[configuration image](../../../README.md#configuration-images) and mounted
read-only where Turf reads it.

## What it creates

- `module.greeting.kubernetes_namespace_v1.this` — the namespace (`turf-greeting`
  by default).
- `module.greeting.kubernetes_config_map_v1.greeting` — a ConfigMap named
  `greeting` in it, holding `var.greeting`.

## Running it

In a pod (the kagent integration), nothing needs setting: the provider finds the
cluster through the pod's service account. From a checkout on a workstation, point
it at a kubeconfig:

```sh
turf -C terraform/kubernetes/in-cluster up -var kubeconfig_path=$HOME/.kube/config
```

The configuration declares no backend, because as an image it is read-only and the
deployment that runs it names one when it opens a workspace — the kagent agent
opens every workspace on the Kubernetes backend:

```
open({
  workspace_name: "greeting", workspace_alias: "greeting",
  backend_type: "kubernetes",
  backend_config: { secret_suffix: "turf", namespace: "kagent", in_cluster_config: true }
})
```

## As an image

The tag `terraform/kubernetes/in-cluster/vX.Y.Z` publishes
`ghcr.io/turfbuild/turf-examples/kubernetes-in-cluster:X.Y.Z`. The lock file is
committed for linux/amd64, linux/arm64, darwin/arm64 and darwin/amd64, since
nothing can write it where the image is mounted; after changing a provider
constraint, run it again before tagging:

```sh
tofu -chdir=terraform/kubernetes/in-cluster providers lock \
  -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=darwin_amd64
```
