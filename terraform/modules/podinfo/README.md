# `modules/podinfo`

[podinfo](https://github.com/stefanprodan/podinfo) as a child module: one
`helm_release`, no provider block, so a root configures `helm` and calls this —
locally, or **pinned to a commit of this repository** from anywhere:

```hcl
module "app" {
  source           = "git::https://github.com/turfbuild/turf-examples.git//terraform/modules/podinfo?ref=<commit>"
  cluster_endpoint = kind_cluster.demo.endpoint
}
```

[`use-cases/guardrails`](../../../use-cases/guardrails/README.md) is the caller
that pins it. `terraform/kubernetes/kind-helm` is the same workload written as a
root, with the cluster rollover explained.
