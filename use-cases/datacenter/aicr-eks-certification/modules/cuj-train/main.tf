# AICR UAT's training CUJ (phase_train, tests/uat/lib/phases.sh): a two-node
# PyTorch MNIST TrainJob on the torch-distributed ClusterTrainingRuntime that
# the bundle's kubeflow-trainer-post chart ships, in the `kubeflow` namespace
# the kubeflow-trainer release creates. UAT applies it with kubectl and polls
# the Complete/Failed conditions every 15s for 20 minutes; here the poll is an
# action on the resource.

resource "terraform_data" "after" {
  triggers_replace = {
    cluster       = var.cluster_endpoint
    certification = var.certification_uid
  }
}

resource "kubernetes_manifest" "trainjob" {
  manifest = {
    apiVersion = "trainer.kubeflow.org/v1alpha1"
    kind       = "TrainJob"
    metadata = {
      name      = var.settings.name
      namespace = var.settings.namespace
    }
    spec = {
      trainer = {
        numNodes = var.settings.num_nodes
        image    = var.settings.image
        command  = ["python3", "/opt/mnist/src/mnist.py", "--epochs=1"]
        resourcesPerNode = {
          requests = { "nvidia.com/gpu" = tostring(var.settings.gpus_per_node) }
          limits   = { "nvidia.com/gpu" = tostring(var.settings.gpus_per_node) }
        }
      }
      runtimeRef = {
        name     = var.settings.runtime
        apiGroup = "trainer.kubeflow.org"
        kind     = "ClusterTrainingRuntime"
      }
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.after]

    action_trigger {
      events     = [after_create]
      actions    = [action.kubewait_condition.trainjob_finished]
      on_failure = taint
    }
  }
}

action "kubewait_condition" "trainjob_finished" {
  config {
    api_version        = "trainer.kubeflow.org/v1alpha1"
    kind               = "TrainJob"
    namespace          = var.settings.namespace
    name               = var.settings.name
    success_conditions = [{ type = "Complete", status = "True" }]
    failure_conditions = [{ type = "Failed", status = "True" }]
    absent             = "failure"
    timeout            = var.settings.timeout
    poll_interval      = "15s"
    progress_fields    = ["status.conditions"]
  }
}
