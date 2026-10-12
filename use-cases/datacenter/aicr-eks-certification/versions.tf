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

    # kubewait_condition (kubewait-action.md). Published on registry.terraform.io
    # only, so the source names that host: OpenTofu resolves an unqualified
    # source against registry.opentofu.org, which does not carry it.
    kubewait = { source = "registry.terraform.io/turfbuild/kubewait", version = "~> 0.1" }
  }

  # Every turf-examples configuration keeps state locally. Upstream keyed an S3
  # backend by deployment (deployments/<region>/<id>/terraform.tfstate) with no
  # locking; for real use, bind a workspace backend with locking, e.g.
  #   backend "s3" { use_lockfile = true }
  backend "local" {
    path = "terraform.tfstate"
  }
}
