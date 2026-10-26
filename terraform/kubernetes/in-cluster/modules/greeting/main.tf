terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "namespace" {
  type = string
}

variable "greeting" {
  type = string
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "turf"
    }
  }
}

resource "kubernetes_config_map_v1" "greeting" {
  metadata {
    name      = "greeting"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  data = {
    greeting = var.greeting
  }
}

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "config_map" {
  value = "${kubernetes_config_map_v1.greeting.metadata[0].namespace}/${kubernetes_config_map_v1.greeting.metadata[0].name}"
}
