# A local Kubernetes cluster running as Docker containers via kind.
#
# The name carries a generation suffix so a replacement can stand the new cluster
# up before the old one comes down: kind cluster names are unique, so two
# generations cannot share one.
#
# There is deliberately no lifecycle block here. The modules below declare
# create_before_destroy, and Turf forces it onto the cluster that holds them —
# declaring it by hand would hide whether that happened.
resource "kind_cluster" "dc" {
  name           = "${var.cluster_name}-${var.generation}"
  node_image     = var.node_image
  wait_for_ready = true
}

# cert-manager, first and only because the NIM webhook needs it.
#
# The NIM chart creates an Issuer and a Certificate to mint the webhook's serving
# cert. Those kinds have to exist before that release is rendered, which is what
# the depends_on below buys. With the webhook off, this whole module drops out —
# the count is the honest statement that cert-manager is here for one reason.
module "cert_manager" {
  source = "./modules/cert-manager"
  count  = var.enable_admission_controller ? 1 : 0

  chart_version    = var.cert_manager_version
  cluster_endpoint = kind_cluster.dc.endpoint
}

# The GPU Operator. On this cluster it will install its control plane, run Node
# Feature Discovery, find no PCI vendor 10de, and create no operands at all.
# Its ClusterPolicy reports Ready with reason NoGPUNodes — see the README.
module "gpu_operator" {
  source = "./modules/gpu-operator"

  chart_version    = var.gpu_operator_version
  driver_enabled   = var.gpu_driver_enabled
  toolkit_enabled  = var.gpu_toolkit_enabled
  cluster_endpoint = kind_cluster.dc.endpoint
}

# The NIM Operator.
#
# `upstream` names both of the others, for two different reasons:
#
#   cert_manager — hard. The release does not render without the Issuer and
#   Certificate CRDs.
#
#   gpu_operator — soft, and honest about being soft. The NIM controller starts
#   perfectly well with no GPU Operator present; NVIDIA lists it as a
#   prerequisite because *reconciling a NIMCache or NIMService* needs the NFD
#   labels and device plugin the GPU Operator provides. Ordering the installs
#   costs nothing and matches the documented dependency.
#
# This is a list of release ids rather than `depends_on = [module.cert_manager,
# module.gpu_operator]` because Turf's Restate engine refuses depends_on on a
# module call — loudly, rather than silently ignoring it. Binding the values is
# the portable spelling, and it says more: these releases are not merely earlier,
# they are what this one is built on.
module "nim_operator" {
  source = "./modules/nim-operator"

  chart_version                = var.nim_operator_version
  admission_controller_enabled = var.enable_admission_controller
  cluster_endpoint             = kind_cluster.dc.endpoint

  upstream = concat(
    module.cert_manager[*].release_id,
    [module.gpu_operator.release_id],
  )
}

# ExternalDNS — what would publish a NIMService's hostname on a real cluster.
# Here it reconciles against an in-memory zone, so it needs no credentials.
module "external_dns" {
  source = "./modules/external-dns"
  count  = var.enable_external_dns ? 1 : 0

  chart_version    = var.external_dns_version
  dns_provider     = var.dns_provider
  domain_filters   = var.domain_filters
  cluster_endpoint = kind_cluster.dc.endpoint
}
