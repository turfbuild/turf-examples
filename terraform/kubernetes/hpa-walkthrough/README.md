# Horizontal Pod Autoscaler walkthrough

Deploy the upstream Kubernetes
[Horizontal Pod Autoscaler walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
— the `php-apache` workload plus an HPA — to an existing cluster with Turf.

## What This Demonstrates

The `kubernetes_horizontal_pod_autoscaler_v1` controller adjusts the Deployment's
replica count at runtime. If Turf owned `spec.replicas`, every re-plan would see the
autoscaler's changes as drift and try to reset them. The Deployment declares
`lifecycle { ignore_changes = [spec[0].replicas] }` so Turf provisions the initial
shape and then hands replica count to the HPA — a clean split of ownership between
declarative config and a runtime controller.

## Resources Created

- `kubernetes_namespace.app` — a dedicated namespace (`hpa-example` by default).
- `kubernetes_deployment_v1.php_apache` — the `registry.k8s.io/hpa-example`
  workload, CPU-limited so the HPA has something to measure.
- `kubernetes_service_v1.php_apache` — a ClusterIP service in front of it.
- `kubernetes_horizontal_pod_autoscaler_v1.php_apache` — scales the Deployment
  between `min_replicas` and `max_replicas` toward a target CPU utilization.

## Prerequisites

- An **existing Kubernetes cluster** and a kubeconfig (`~/.kube/config` by default;
  override with the `kubeconfig_path` / `kubeconfig_context` variables).
- The Turf CLI, or any MCP client pointed at `turf-mcp-server`.

> The manifests apply on any cluster, but the HPA only actually *scales* on a cluster
> running [metrics-server](https://github.com/kubernetes-sigs/metrics-server). Without
> it the HPA stays at `min_replicas` (target utilization reads as `<unknown>`).

## Usage

```bash
turf -C terraform/kubernetes/hpa-walkthrough up
```

## Verify

```bash
kubectl -n hpa-example get deploy,svc,hpa
```

To watch it scale (needs metrics-server), generate load per the upstream walkthrough:

```bash
kubectl -n hpa-example run -it --rm load-generator --image=busybox:1.28 --restart=Never \
  -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
kubectl -n hpa-example get hpa php-apache --watch
```

## Cleanup

```bash
turf -C terraform/kubernetes/hpa-walkthrough destroy
```
