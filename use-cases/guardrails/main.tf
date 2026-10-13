# What is deployed: a kind cluster and podinfo in it, the module pinned to a
# commit of this repository. The three guardrails around it are elsewhere:
# the provider scan reads what init reports (README), the policy reads the
# plan at the approval point (policies/), and guardrails.turf.hcl makes both
# a step of the apply itself.

resource "kind_cluster" "demo" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true
}

# The release's name suffix. One word is too short to read, which is what the
# policy says; two is the fix.
resource "random_pet" "name" {
  length = var.length
}

# A versioned configuration: the module is a ref of this repository, so the
# workload you deploy is exactly the commit you reviewed. A module source
# cannot read a variable, so the ref is spelled here; var.app_ref records it
# for the plan and the README.
module "app" {
  source = "git::https://github.com/turfbuild/turf-examples.git//terraform/modules/podinfo?ref=21fd4fb6967e2870f6ee3436d68be6f12465d614"

  name             = "podinfo-${random_pet.name.id}"
  cluster_endpoint = kind_cluster.demo.endpoint
}
