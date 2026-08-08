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

variable "coded_workspace_name" {
  description = "State-storage-only workspace backing the coded example (../state-backend)."
  type        = string
  default     = "turf-scalr-coded"
}

variable "plot_workspace_name" {
  description = "State-storage-only workspace backing the plot example (../plot)."
  type        = string
  default     = "turf-scalr-plot"
}

variable "vcs_token" {
  description = "OAuth / personal access token for the GitHub VCS provider used to source the OPA policies. Leave empty to skip the VCS provider + policy group (the environment and workspaces are still created)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "policy_repo" {
  description = "org/repo hosting the OPA policies (this repo, by default)."
  type        = string
  default     = "turfbuild/turf-examples"
}

variable "policy_path" {
  description = "Subdirectory in policy_repo containing scalr-policy.hcl + *.rego."
  type        = string
  default     = "integrations/scalr/policies"
}
