terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }

    # See the root versions.tf. Every module that declares a kubewait action
    # repeats the binding.
    kubewait = { source = "turfbuild/kubewait", version = "~> 0.1" }
  }
}
