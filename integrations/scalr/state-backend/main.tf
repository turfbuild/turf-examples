# A trivial, credential-free workload so there's real state to persist in Scalr.
resource "random_pet" "name" {
  length = 2
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}
