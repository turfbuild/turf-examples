terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }

    # See the root versions.tf.
    kubewait = { source = "turfbuild/kubewait", version = "~> 0.1" }
  }
}
