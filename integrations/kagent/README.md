# Turf in kagent

The kagent integration lives in its own repository now:
**[turfbuild/turf-kagent](https://github.com/turfbuild/turf-kagent)**.

It runs Turf with kagent 1.0: the agent in a gVisor sandbox, Turf's MCP server behind a bearer
token that kagent's egress gateway adds, restate-server as a RestateCluster and the engine as a
Knative service under the Restate operator, OpenTofu state in Kubernetes Secrets, network policies
around every part, and a person approving every apply in the kagent UI.

The manifests that were here targeted kagent 0.10.3, whose `MCPServer` kind kagent 1.0 removed.
They are in this repository's history, at the commit before this README replaced them.

The configuration the agent operates is still published from this repository, as the
configuration image `ghcr.io/turfbuild/turf-examples/kubernetes-in-cluster`
([`terraform/kubernetes/in-cluster`](../../terraform/kubernetes/in-cluster)).
