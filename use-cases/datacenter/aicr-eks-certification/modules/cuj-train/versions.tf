terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }

    # STAND-IN for turfbuild/kubewait: see the root versions.tf.
    kubewait = { source = "hashicorp/tfcoremock", version = "0.6.0-beta2" }
  }
}
