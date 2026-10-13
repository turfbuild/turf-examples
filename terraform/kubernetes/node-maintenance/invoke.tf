# Only for the imperative alternative in the README's appendix: an uncordon
# keyed by node, for `terraform apply -invoke`. The declarative flow uses
# action.local_command.release instead.
action "local_command" "uncordon" {
  for_each = local.nodes
  config {
    command   = "kubectl"
    arguments = concat(["uncordon", each.key], local.kubectl_flags)
  }
}
