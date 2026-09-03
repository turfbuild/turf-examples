variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix for the execution role and every function name."
  type        = string
  default     = "turf-hello"
}

variable "fleet_size" {
  description = "Number of Lambda functions to deploy."
  type        = number
  default     = 5

  validation {
    condition     = var.fleet_size > 0 && var.fleet_size <= 200
    error_message = "fleet_size must be between 1 and 200."
  }
}

variable "greeting" {
  description = "Value of the GREETING environment variable on every function. Change it to patch the fleet."
  type        = string
  default     = "Hello, World!"
}

variable "runtime" {
  description = "Lambda runtime for the handler."
  type        = string
  default     = "nodejs22.x"
}
