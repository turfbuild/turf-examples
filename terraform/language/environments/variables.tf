variable "environment" {
  description = "The environment this stack is: staging or production. Comes from env/<name>.tfvars, never from the workspace name."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "app_version" {
  description = "The service version this configuration deploys. Bump it, plan staging, then plan production."
  type        = string
  default     = "1.0.0"
}

variable "replicas" {
  description = "How many replicas the environment runs"
  type        = number
}
