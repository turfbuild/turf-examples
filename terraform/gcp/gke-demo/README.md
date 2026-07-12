# GKE Autopilot Demo

This example creates a GKE Autopilot cluster with custom VPC networking.

## Resources Created

- `google_compute_network.vpc` - VPC network
- `google_compute_subnetwork.subnet` - Subnet with secondary ranges for pods/services
- `google_container_cluster.primary` - GKE Autopilot cluster

## Prerequisites

1. GCP project with billing enabled
2. APIs enabled: Compute Engine, Kubernetes Engine
3. Authentication configured (`gcloud auth application-default login`)
4. Copy `terraform.tfvars.example` to `terraform.tfvars` and set your `project_id`

## Usage

```bash
turf -C terraform/gcp/gke-demo up
```

## Outputs

- `cluster_endpoint` - Kubernetes API endpoint (sensitive)
- `cluster_name` - Cluster name
- `kubeconfig_command` - Command to configure kubectl

## Cleanup

```bash
turf -C terraform/gcp/gke-demo destroy
```
