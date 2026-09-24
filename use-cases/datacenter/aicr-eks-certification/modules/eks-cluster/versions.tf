terraform {
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 6.47" }
    http = { source = "hashicorp/http", version = "~> 3.5" }
    tls  = { source = "hashicorp/tls", version = "~> 4.1" }
  }
}
