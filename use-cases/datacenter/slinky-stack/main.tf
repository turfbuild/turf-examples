# Slurm on Kubernetes, the way NVIDIA's Run:ai tutorial deploys it — with the
# Run:ai part swapped for KAI Scheduler, the open-source scheduler inside it.
#
#   kind_cluster.dc
#     ├─ cert_manager ──────────► slurm_operator ──┐ depends_on: CRDs served,
#     │                                            │ webhook up, finalizers last
#     ├─ gpu_operator ── dcgm_job_mapping_dir ─────┤
#     └─ kai_scheduler ─ scheduler_name, queue ────┴─► slurm
#
# Two of slurm's three edges carry a value; the third is order only. Each is
# explained where it is declared.

# A control plane and `worker_count` workers. The Slurm operator gives every
# slurmd pod a required anti-affinity against every other slurmd pod — one Slurm
# node per Kubernetes node — so a two-node CPU partition needs two workers.
#
# The name carries a generation suffix so a replacement can stand the new cluster
# up before the old one comes down: kind cluster names are unique.
resource "kind_cluster" "dc" {
  name           = "${var.cluster_name}-${var.generation}"
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

# cert-manager, because the Slurm operator's webhook asks for it: with the
# chart's default certManager.enabled=true it renders an Issuer chain and a
# Certificate for the webhook's serving cert.
module "cert_manager" {
  source = "./modules/cert-manager"

  chart_version    = var.cert_manager_version
  cluster_endpoint = kind_cluster.dc.endpoint
}

# The operator and its six CRDs.
#
# depends_on cert_manager is hard: the release contains cert-manager kinds, so
# it cannot be applied before they are served.
module "slurm_operator" {
  source = "./modules/slurm-operator"

  chart_version    = var.slinky_version
  cluster_endpoint = kind_cluster.dc.endpoint

  depends_on = [module.cert_manager]
}

# The GPU Operator. On kind it installs, runs Node Feature Discovery, finds no
# NVIDIA PCI device and deploys no operands — no driver, no device plugin, no
# DCGM exporter. Nothing on this cluster will ever advertise nvidia.com/gpu.
module "gpu_operator" {
  source = "./modules/gpu-operator"

  chart_version       = var.gpu_operator_version
  driver_enabled      = var.gpu_driver_enabled
  toolkit_enabled     = var.gpu_toolkit_enabled
  hpc_job_mapping_dir = var.dcgm_job_mapping_dir
  cluster_endpoint    = kind_cluster.dc.endpoint
}

# KAI Scheduler, the department and project queues, and the pod-grouper's read
# access to NodeSets.
module "kai_scheduler" {
  source = "./modules/kai-scheduler"
  count  = var.use_kai_scheduler ? 1 : 0

  chart_version    = var.kai_scheduler_version
  department       = var.queue_department
  project          = var.queue_name
  gpu_quota        = var.queue_gpu_quota
  gpu_limit        = var.queue_gpu_limit
  cluster_endpoint = kind_cluster.dc.endpoint
}

# The Slurm cluster: controller, REST API, a login node, a CPU NodeSet and a GPU
# NodeSet, in one partition.
#
#   scheduler — a value edge from KAI. The module's queue output is ordered
#   after the queue exists, so no Slurm pod is ever created naming a queue that
#   is not there. With use_kai_scheduler off this is null and every pod goes to
#   the default scheduler, which is the tutorial minus Run:ai.
#
#   dcgm_job_mapping_dir — a value edge from the GPU Operator. Slurm's prolog
#   writes which job holds which GPU into a host directory; DCGM exporter reads
#   the same directory. Two vendors' charts default to the same path, but only
#   by convention; binding one to the other's output makes it a fact.
#
#   depends_on slurm_operator — order only, and needed three ways: the CRDs
#   must be served; the validating webhook fails closed, so it must be up; and
#   on destroy the operator has to outlive the objects it finalizes.
module "slurm" {
  source = "./modules/slurm"

  chart_version            = var.slinky_version
  cpu_nodeset_replicas     = var.cpu_nodeset_replicas
  gpu_nodeset              = var.gpu_nodeset
  non_preemptible          = var.slurm_non_preemptible
  root_ssh_authorized_keys = var.root_ssh_authorized_keys
  login_service_type       = var.login_service_type
  dcgm_job_mapping_dir     = module.gpu_operator.dcgm_job_mapping_dir
  cluster_endpoint         = kind_cluster.dc.endpoint

  scheduler = var.use_kai_scheduler ? {
    name        = module.kai_scheduler[0].scheduler_name
    queue_label = module.kai_scheduler[0].queue_label
    queue       = module.kai_scheduler[0].queue
  } : null

  depends_on = [module.slurm_operator]
}
