# One configuration, one stack per environment. Nothing here knows which
# environment it is: var.environment and var.replicas come from env/*.tfvars,
# and the workspace name — staging, production — picks the state slot. Promote
# a change by bumping var.app_version, planning staging, then planning production
# with the same files.

resource "random_pet" "name" {
  length = 2
}

# A mock "service" standing in for a deployment; its string carries everything
# a promotion changes, so the plan shows the diff plainly.
resource "tfcoremock_simple_resource" "service" {
  string  = "${var.environment}/${random_pet.name.id} v${var.app_version}"
  integer = var.replicas
}
