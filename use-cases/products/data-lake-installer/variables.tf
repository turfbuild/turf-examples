# The install questionnaire. What init reports under variables[] with no
# default is what the customer supplies; everything else is the product's.

variable "product_name" {
  description = "The product being installed; prefixes every resource name"
  type        = string
}

variable "tenant" {
  description = "The customer's tenant identifier (lowercase, DNS-safe); the lake's buckets carry it"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.tenant))
    error_message = "tenant must be 3–32 lowercase letters, digits or hyphens."
  }
}

variable "region" {
  description = "AWS region the lake lives in"
  type        = string
}

variable "plan_only" {
  description = "true plans with no AWS credentials (mock keys, API checks skipped) and must never be applied; false installs for real with the customer's credentials"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR of the lake's VPC"
  type        = string
  default     = "10.40.0.0/16"
}
