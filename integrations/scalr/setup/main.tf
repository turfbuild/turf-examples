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
resource "scalr_workspace" "chat" {
  name           = var.chat_workspace_name
  environment_id = scalr_environment.demo.id
  execution_mode = "local"
  iac_platform   = "opentofu"
}

# A demo Terraform variable, scoped to the chat workspace. Read it back later via
# the Scalr MCP server (list_variables) — variables-as-code alongside the state.
resource "scalr_variable" "greeting" {
  key          = "greeting"
  value        = "hello-from-scalr"
  category     = "terraform"
  description  = "Demo variable surfaced through the Scalr MCP server."
  workspace_id = scalr_workspace.chat.id
}

# A non-sensitive region value. A LOCAL turf session pulls this through the Scalr
# MCP server (scalr_get_variable) and feeds it into a Scalr registry module — one
# of the "compose remote features locally" demos. Non-sensitive on purpose:
# sensitive Scalr variables are write-once and never returned by the API.
resource "scalr_variable" "region" {
  key          = "region"
  value        = "us-east-1"
  category     = "terraform"
  description  = "Demo region, pulled by a local turf session via the Scalr MCP server and fed into a module."
  workspace_id = scalr_workspace.chat.id
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
  count           = local.vcs_enabled && var.enable_policy_group ? 1 : 0
  name            = "turf-demo-guardrails"
  account_id      = local.account_id
  vcs_provider_id = scalr_vcs_provider.github[0].id

  vcs_repo {
    identifier = var.policy_repo
    path       = var.policy_path
    branch     = var.policy_branch != "" ? var.policy_branch : null
  }
}

resource "scalr_policy_group_linkage" "demo" {
  count           = local.vcs_enabled && var.enable_policy_group ? 1 : 0
  policy_group_id = scalr_policy_group.opa[0].id
  environment_id  = scalr_environment.demo.id
}

# Publish modules into the Scalr private registry so a LOCAL turf session can pull
# them by their four-part source (turf.scalr.io/<namespace>/<name>/<provider>) and
# news them up with a Scalr-sourced variable. Mirrors the Scalr docs' example
# modules (forks of terraform-aws-modules/*). A repo named terraform-aws-vpc yields
# name=vpc, provider=aws; versions come from the repo's semver tags.
#
# Scalr installs a tag webhook on each repo, so these must be repos YOU administer
# (that's why they're forks under your account, not the upstream terraform-aws-modules
# org). Scalr's registry organizes modules under account-level *namespaces* (the API
# requires the relationship); the namespace name is the second segment of the source.
resource "scalr_module_namespace" "demo" {
  count        = local.vcs_enabled ? 1 : 0
  name         = var.environment_name
  environments = [scalr_environment.demo.id]
}

resource "scalr_module" "registry" {
  for_each        = local.vcs_enabled ? var.module_repos : {}
  vcs_provider_id = scalr_vcs_provider.github[0].id
  namespace_id    = scalr_module_namespace.demo[0].id

  vcs_repo {
    identifier = each.value
    tag_prefix = var.module_tag_prefix
  }
}
