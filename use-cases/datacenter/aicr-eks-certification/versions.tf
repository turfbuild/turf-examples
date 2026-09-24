terraform {
  # Destroy-event action triggers (before_destroy / after_destroy) and
  # action_trigger.on_failure first appear in Terraform 1.16.0: 1.14.0 and
  # 1.15.0 reject both (measured). The aws/kubernetes/helm pins match the
  # ported modules and the generated bundle.
  required_version = ">= 1.16.0"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.47" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
    helm       = { source = "hashicorp/helm", version = "~> 3.0" }
    http       = { source = "hashicorp/http", version = "~> 3.5" }
    tls        = { source = "hashicorp/tls", version = "~> 4.1" }

    # STAND-IN. `kubewait` is specified, not built (kubewait-action.md). The
    # local name is bound to tfcoremock, which serves every schema in
    # dynamic_resources.json as an action, so `terraform validate` type-checks
    # each kubewait_condition config against the spec. Only the behaviour is
    # imagined. To switch to the real provider, change this source and delete
    # dynamic_resources.json:
    #   kubewait = { source = "turfbuild/kubewait" }
    kubewait = { source = "hashicorp/tfcoremock", version = "0.6.0-beta2" }
  }

  # Every turf-examples configuration keeps state locally. Upstream keyed an S3
  # backend by deployment (deployments/<region>/<id>/terraform.tfstate) with no
  # locking; for real use, bind a workspace backend with locking, e.g.
  #   backend "s3" { use_lockfile = true }
  backend "local" {
    path = "terraform.tfstate"
  }
}
