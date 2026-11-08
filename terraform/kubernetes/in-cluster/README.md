# In-cluster greeting

A namespace, a ConfigMap and a Job that prints it, written through a local
module by the Kubernetes provider using the service account of the pod it runs
in, with a turf action that waits for the Job. It is small on purpose:
this is the configuration [turfbuild/turf-kagent](https://github.com/turfbuild/turf-kagent) runs, published as a
[configuration image](../../../README.md#configuration-images) and mounted
read-only where Turf reads it.

## What it creates

- `module.greeting.kubernetes_namespace_v1.this` — the namespace (`turf-greeting`
  by default).
- `module.greeting.kubernetes_config_map_v1.greeting` — a ConfigMap named
  `greeting` in it, holding `var.greeting`.
- `module.greeting.kubernetes_job_v1.greet` — a one-pod Job that prints the
  greeting from the ConfigMap. The apply does not wait for it: the turf action
  below does.

## The turf action

`greeting.turf.hcl` declares a `turf_action` bound after the Job's creation: a
step of the apply that the agent carries out with its own tools instead of a
provider. The apply pauses there, the agent watches the Job (its status, its
pod's events and log) and reports that it succeeded, quoting the greeting, or
that it failed, with the log as the error, which halts the round. tofu and
terraform ignore the file by its name; Turf lays it over the configuration at
every plan. With `turf up` and no agent in the loop, the step is asked at the
approval point like any other.

## Running it

In a pod (as in turf-kagent), nothing needs setting: the provider finds the
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
  backend_config: { secret_suffix: "turf", namespace: "turf", in_cluster_config: true }
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
