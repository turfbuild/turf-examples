terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.47" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
  }
}
