# Scalr OPA policy manifest. Scalr reads this file from the policy group's VCS repo
# (see ../setup: scalr_policy_group.vcs_repo.path) and applies each named policy's
# enforcement level to the *.rego of the same name in this directory.
#
# enforcement_level:
#   hard-mandatory — a violation errors the run (blocks apply)
#   soft-mandatory — a violation errors the run, but can be overridden with approval
#   advisory       — a violation only warns; the run continues
version = "v1"

policy "readable_pet_names" {
  enabled           = true
  enforcement_level = "hard-mandatory"
}

policy "require_environment_tag" {
  enabled           = true
  enforcement_level = "hard-mandatory"
}
