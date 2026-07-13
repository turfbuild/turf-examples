# A dependency chain: random_pet.server references both random_integer.port and
# random_password.secret through its keepers. The keeper references make `server`
# depend on `port` and `secret`, so the effect compiler must order any
# replacement of all three correctly.
resource "random_integer" "port" {
  min = 10000
  max = 20000
}

resource "random_password" "secret" {
  length = 16
}

resource "random_pet" "server" {
  keepers = {
    port   = random_integer.port.result
    secret = random_password.secret.result
  }

  # Uncomment to switch from the delete-then-create scenario to the forced
  # create-before-destroy scenario (see README.md). With this set, `server` is
  # create-before-destroy and turf forces `port` and `secret` to CBD too — the
  # infectious-CBD rule — so the teardown does not cycle.
  #
  # lifecycle {
  #   create_before_destroy = true
  # }
}
