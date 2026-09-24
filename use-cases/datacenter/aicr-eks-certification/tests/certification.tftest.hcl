# modules/certification: what the Certification spec says, what the waits are
# configured to check, and what makes a certificate stale. The waits are the
# tfcoremock stand-in (mocked here); these runs check the wiring, not the
# behaviour kubewait-action.md specifies.

mock_provider "kubernetes" {
  # kubernetes_manifest.object is what the API server returned; give the mock a UID.
  mock_resource "kubernetes_manifest" {
    defaults = {
      object = { metadata = { uid = "00000000-0000-0000-0000-000000000000" } }
    }
  }
}
mock_provider "kubewait" {}

override_data {
  target = data.kubernetes_nodes.gpu
  values = {
    nodes = [
      {
        metadata = [{ name = "ip-10-0-200-7.ec2.internal", labels = { nodeGroup = "gpu-worker" } }]
        spec     = [{ provider_id = "aws:///us-east-1e/i-0bbbbbbbbbbbbbbbb" }]
      },
      {
        metadata = [{ name = "ip-10-0-130-4.ec2.internal", labels = { nodeGroup = "gpu-worker" } }]
        spec     = [{ provider_id = "aws:///us-east-1e/i-0aaaaaaaaaaaaaaaa" }]
      },
    ]
  }
}

variables {
  cluster_endpoint = "https://tftest.example"
  cluster_version  = "1.35"
  expected_nodes   = 2
  stack_revision   = "0000"
  pool_identity = {
    gpu-worker = { launch_template_id = "lt-0123", launch_template_version = 1, autoscaling_group = "tftest-gpu-worker" }
  }
  settings = {
    pools         = ["gpu-worker"]
    node_selector = { nodeGroup = "gpu-worker" }
    name          = "gpu-pools"
    namespace     = "nvcre-certification"
    categories = [
      { domain = "communication", variant = "nccl-all-reduce", options = null },
      { domain = "training", variant = "nemotron5-8b", options = { maxSteps = 20 } },
    ]
    options         = { thresholds = { busBandwidthGBps = "value >= 300" } }
    taint_selectors = [{ key = "dedicated", value = "worker-workload", effect = null }]
    gang_scheduler  = { scheduler_name = "kai-scheduler", queue = null }
    gpus_per_node   = 8
    census_timeout  = "30m"
    wait_timeout    = "60m"
    settle          = "2m"
    drain_timeout   = "10m"
  }
}

run "spec_targets_the_named_nodes" {
  command = plan
  module {
    source = "./modules/certification"
  }

  # ADR-025 decision 6: the caller bounds the footprint with target.nodeNames.
  assert {
    condition     = local.spec.target.nodeNames == tolist(["ip-10-0-130-4.ec2.internal", "ip-10-0-200-7.ec2.internal"])
    error_message = "target.nodeNames must be the selected nodes, sorted"
  }

  assert {
    condition     = local.spec.target.taintSelectors == [{ key = "dedicated", value = "worker-workload" }]
    error_message = "unset taint selector fields are omitted, not sent as null"
  }

  assert {
    condition     = local.spec.gangScheduler == { schedulerName = "kai-scheduler" }
    error_message = "gangScheduler omits an unset queue"
  }

  assert {
    condition = (
      local.spec.categories[0] == { domain = "communication", variant = "nccl-all-reduce" } &&
      local.spec.categories[1].options.maxSteps == 20
    )
    error_message = "categories carry per-category options only when set"
  }

  assert {
    condition     = local.spec.thresholds.busBandwidthGBps == "value >= 300"
    error_message = "spec-level options are the inline CategoryOptions"
  }

  assert {
    condition = (
      kubernetes_manifest.certification.manifest.apiVersion == "nvcre.nvidia.com/v1alpha1" &&
      kubernetes_manifest.certification.manifest.kind == "Certification" &&
      kubernetes_manifest.certification.manifest.metadata.namespace == "nvcre-certification"
    )
    error_message = "the manifest is an nvcre.nvidia.com/v1alpha1 Certification in the configured namespace"
  }
}

run "certificate_is_of_these_instances" {
  command = plan
  module {
    source = "./modules/certification"
  }

  assert {
    condition     = terraform_data.identity.triggers_replace.instances == tolist(["aws:///us-east-1e/i-0aaaaaaaaaaaaaaaa", "aws:///us-east-1e/i-0bbbbbbbbbbbbbbbb"])
    error_message = "the identity carries the nodes' EC2 instance IDs, so a replaced instance means a new certificate"
  }

  assert {
    condition     = terraform_data.identity.triggers_replace.pools["gpu-worker"].launch_template_version == 1
    error_message = "the identity carries each certified pool's launch template version"
  }
}

# The identity is the whole point: apply once, then show that re-applying the
# same inputs keeps the certificate, and that booting the pool from a new launch
# template version makes a new one (the spec is immutable, so the Certification
# is replaced through replace_triggered_by = [terraform_data.identity]). Runs in
# one file share state.
run "apply_first_certification" {
  command = apply
  module {
    source = "./modules/certification"
  }
}

run "same_inputs_keep_the_certificate" {
  command = apply
  module {
    source = "./modules/certification"
  }

  assert {
    condition     = output.identity == run.apply_first_certification.identity
    error_message = "re-applying unchanged inputs must not re-certify"
  }
}

run "new_launch_template_version_makes_a_new_certificate" {
  command = apply
  module {
    source = "./modules/certification"
  }

  variables {
    pool_identity = {
      gpu-worker = { launch_template_id = "lt-0123", launch_template_version = 2, autoscaling_group = "tftest-gpu-worker" }
    }
  }

  assert {
    condition     = output.identity != run.apply_first_certification.identity
    error_message = "a new launch template version must replace the identity, and with it the Certification"
  }
}
