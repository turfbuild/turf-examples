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

## Usage with Turf

```bash
/up terraform/gcp/gke-demo
```

## Usage with OpenTofu/Terraform

```bash
cd terraform/gcp/gke-demo
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID

tofu init
tofu plan
tofu apply
```

## Outputs

- `cluster_endpoint` - Kubernetes API endpoint (sensitive)
- `cluster_name` - Cluster name
- `kubeconfig_command` - Command to configure kubectl

## Cleanup

```bash
tofu destroy
```
