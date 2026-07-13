# Dedicated namespace for the HPA example workload
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
  }
}

# php-apache deployment from the Kubernetes HPA walkthrough
# https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
resource "kubernetes_deployment_v1" "php_apache" {
  metadata {
    name      = "php-apache"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      run = "php-apache"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        run = "php-apache"
      }
    }

    template {
      metadata {
        labels = {
          run = "php-apache"
        }
      }

      spec {
        container {
          name  = "php-apache"
          image = "registry.k8s.io/hpa-example"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu = "500m"
            }
            requests = {
              cpu = "200m"
            }
          }
        }
      }
    }
  }

  # The HPA controller manages replica count dynamically.
  # Without this, every reconciliation would detect the HPA-adjusted
  # replica count as drift and attempt to reset it.
  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

# ClusterIP service exposing the php-apache deployment
resource "kubernetes_service_v1" "php_apache" {
  metadata {
    name      = "php-apache"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = {
      run = "php-apache"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# Horizontal Pod Autoscaler targeting the php-apache deployment
resource "kubernetes_horizontal_pod_autoscaler_v1" "php_apache" {
  metadata {
    name      = "php-apache"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    min_replicas                      = var.min_replicas
    max_replicas                      = var.max_replicas
    target_cpu_utilization_percentage = var.target_cpu_utilization

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.php_apache.metadata[0].name
    }
  }
}
