variable "cluster_name" {
  description = "Base name of the kind cluster; the generation suffix is appended"
  type        = string
  default     = "slinky"
}

variable "generation" {
  description = "Cluster generation; change it to roll the cluster and everything inside it"
  type        = string
  default     = "1"
}

variable "node_image" {
  description = "kind node image (pins the Kubernetes version)"
  type        = string
  default     = "kindest/node:v1.36.1"
}

variable "worker_count" {
  description = <<-EOT
    kind worker nodes. Each holds at most one slurmd pod (the operator's
    anti-affinity), so this caps the CPU partition.
  EOT
  type        = number
  default     = 2
}

# --- Chart pins -----------------------------------------------------------

variable "cert_manager_version" {
  description = "jetstack/cert-manager chart version"
  type        = string
  default     = "v1.21.2"
}

variable "gpu_operator_version" {
  description = "nvidia/gpu-operator chart version"
  type        = string
  default     = "v26.7.0"
}

variable "kai_scheduler_version" {
  description = "kai-scheduler chart version"
  type        = string
  default     = "v0.18.1"
}

variable "slinky_version" {
  description = "Slinky chart version — slurm-operator-crds, slurm-operator and slurm move together"
  type        = string
  default     = "1.2.2"
}

# --- The Run:ai project, as KAI queues -------------------------------------

variable "use_kai_scheduler" {
  description = <<-EOT
    Schedule every Slurm pod with KAI, in queue `queue_name`. false installs no
    KAI at all and leaves the default scheduler: the tutorial with Run:ai taken
    out. On a real Run:ai cluster, set false and let the project's namespace
    enforcement do this instead.
  EOT
  type        = bool
  default     = true
}

variable "queue_department" {
  description = "KAI parent queue — Run:ai's department"
  type        = string
  default     = "datacenter"
}

variable "queue_name" {
  description = "KAI leaf queue every Slurm pod is placed in — Run:ai's project"
  type        = string
  default     = "slurm"
}

variable "queue_gpu_quota" {
  description = <<-EOT
    GPUs the project queue is guaranteed. The tutorial's prerequisite is "project
    GPU quota sized for the NodeSet request": gpu_nodeset.replicas ×
    gpu_nodeset.gpus_per_node.
  EOT
  type        = number
  default     = 4
}

variable "queue_gpu_limit" {
  description = "Most GPUs the project queue may hold; -1 for no limit"
  type        = number
  default     = -1
}

# --- The Slurm cluster -----------------------------------------------------

variable "cpu_nodeset_replicas" {
  description = "slurmd pods in the CPU NodeSet; at most worker_count (one slurmd per node)"
  type        = number
  default     = 2
}

variable "gpu_nodeset" {
  description = <<-EOT
    The GPU NodeSet, slurm-worker-gpu: replicas, and nvidia.com/gpu requested by
    each slurmd pod. The tutorial's NodeSet asks for 4. null for none.
  EOT
  type = object({
    replicas      = number
    gpus_per_node = number
  })
  default = {
    replicas      = 1
    gpus_per_node = 4
  }
}

variable "slurm_non_preemptible" {
  description = <<-EOT
    Run Slurm pods at Slinky's slurm-system-critical priority, which KAI treats
    as non-preemptible — admitted only within the queue's quota. Run:ai's
    default for a NodeSet.
  EOT
  type        = bool
  default     = true
}

variable "root_ssh_authorized_keys" {
  description = <<-EOT
    Public keys for root on the login pod — the tutorial's
    `--set-file loginsets.slinky.rootSshAuthorizedKeys=~/.ssh/id_ed25519.pub`.
    null means kubectl exec is the only way in.
  EOT
  type        = string
  default     = null
}

variable "login_service_type" {
  description = "Service type for the login pod's sshd; the chart's LoadBalancer default never gets an address on kind"
  type        = string
  default     = "ClusterIP"
}

variable "dcgm_job_mapping_dir" {
  description = <<-EOT
    Host directory through which Slurm tells DCGM exporter which job holds which
    GPU. Set on the GPU Operator and passed from there to the Slurm chart. null
    turns the integration off on both sides.
  EOT
  type        = string
  default     = "/var/lib/dcgm-exporter/job-mapping"
}

variable "gpu_driver_enabled" {
  description = "Have the GPU Operator deploy the NVIDIA driver; false on kind — there is no GPU to drive"
  type        = bool
  default     = false
}

variable "gpu_toolkit_enabled" {
  description = "Have the GPU Operator deploy the NVIDIA container toolkit"
  type        = bool
  default     = false
}
