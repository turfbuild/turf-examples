variable "scalr_hostname" {
  description = "Your Scalr account hostname, e.g. \"example.scalr.io\"."
  type        = string
}

variable "scalr_account_id" {
  description = "Scalr account ID (acc-...). Leave empty to let the provider infer it from your token."
  type        = string
  default     = ""
}

variable "environment_name" {
  description = "Name of the Scalr environment to create. This is the `organization` value in the remote backend blocks of the examples."
  type        = string
  default     = "turf-demo"
}

variable "chat_workspace_name" {
  description = "State-storage-only workspace whose variables the chat/ demo pulls via the Scalr MCP server."
  type        = string
  default     = "turf-scalr-chat"
}

variable "vcs_token" {
  description = "OAuth / personal access token for the GitHub VCS provider used to source the OPA policies. Leave empty to skip the VCS provider + policy group (the environment and workspaces are still created)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_policy_group" {
  description = "Create the remote OPA scalr_policy_group (setup-as-code illustration). Requires the policies to actually exist at policy_repo@policy_branch/policy_path — Scalr reads them from the VCS repo, not locally. The headline mcp/ demo evaluates the same .rego LOCALLY via the OPA MCP server and does NOT need this. Off by default."
  type        = bool
  default     = false
}

variable "policy_repo" {
  description = "org/repo hosting the OPA policies (this repo, by default)."
  type        = string
  default     = "turfbuild/turf-examples"
}

variable "policy_branch" {
  description = "Branch of policy_repo that Scalr reads the policies from. Empty = the repo's default branch."
  type        = string
  default     = ""
}

variable "policy_path" {
  description = "Subdirectory in policy_repo containing scalr-policy.hcl + *.rego."
  type        = string
  default     = "integrations/scalr/policies"
}

variable "module_repos" {
  description = "Modules to publish into the Scalr private registry, keyed by a short label. Each value is an org/terraform-<provider>-<name> repo that YOU administer (Scalr installs a tag webhook, so it must be a repo you own with semver tags — e.g. a fork of the terraform-aws-modules examples). Leave empty to skip module publishing."
  type        = map(string)
  default = {
    vpc = "EronWright/terraform-aws-vpc"
    iam = "EronWright/terraform-aws-iam"
  }
}

variable "module_tag_prefix" {
  description = "Only tags with this prefix become module versions (empty = all semver tags)."
  type        = string
  default     = ""
}
