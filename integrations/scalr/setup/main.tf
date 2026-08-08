locals {
  # account_id is optional on every resource below; null lets the provider infer it
  # from the token when you don't supply one.
  account_id = var.scalr_account_id != "" ? var.scalr_account_id : null

  # The VCS provider + OPA policy group are only created when a VCS token is given.
  # nonsensitive(): whether a token was supplied is not itself a secret, and this
  # boolean drives `count` + an output, neither of which may carry a sensitive value.
  vcs_enabled = nonsensitive(var.vcs_token != "")
}

# The environment. Its NAME is the `organization` the example backends point at.
resource "scalr_environment" "demo" {
  name       = var.environment_name
  account_id = local.account_id
}

# State-storage-only workspaces. execution_mode = "local" means Turf runs the
# plan/apply locally and Scalr only stores the state + variables — no remote run,
# so Turf keeps its agentic loop and there's no run charge.
resource "scalr_workspace" "coded" {
  name           = var.coded_workspace_name
  environment_id = scalr_environment.demo.id
  execution_mode = "local"
  iac_platform   = "opentofu"
}

resource "scalr_workspace" "plot" {
  name           = var.plot_workspace_name
  environment_id = scalr_environment.demo.id
  execution_mode = "local"
  iac_platform   = "opentofu"
}

# A demo Terraform variable, scoped to the coded workspace. Read it back later via
# the Scalr MCP server (list_variables) — variables-as-code alongside the state.
resource "scalr_variable" "greeting" {
  key          = "greeting"
  value        = "hello-from-scalr"
  category     = "terraform"
  description  = "Demo variable surfaced through the Scalr MCP server."
  workspace_id = scalr_workspace.coded.id
}

# --- OPA policy, sourced from this repo over VCS (only when vcs_token is set) -----

resource "scalr_vcs_provider" "github" {
  count      = local.vcs_enabled ? 1 : 0
  name       = "turf-examples-github"
  vcs_type   = "github"
  token      = var.vcs_token
  account_id = local.account_id
}

resource "scalr_policy_group" "opa" {
  count           = local.vcs_enabled ? 1 : 0
  name            = "turf-demo-guardrails"
  account_id      = local.account_id
  vcs_provider_id = scalr_vcs_provider.github[0].id

  vcs_repo {
    identifier = var.policy_repo
    path       = var.policy_path
  }
}

resource "scalr_policy_group_linkage" "demo" {
  count           = local.vcs_enabled ? 1 : 0
  policy_group_id = scalr_policy_group.opa[0].id
  environment_id  = scalr_environment.demo.id
}
