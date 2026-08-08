# A tiny post-plan OPA policy for Scalr. The package MUST be named `terraform`, and
# the rule MUST produce a `deny` array of human-readable strings — that is Scalr's
# OPA contract. Scalr provides the plan JSON at `input.tfplan`.
#
# This one is advisory (see scalr-policy.hcl): it encourages `random_pet` names to
# keep length >= 2 so generated identifiers stay readable. It is deliberately keyed
# to the random workload the examples create, so you can see a policy check evaluate
# against a real plan.
package terraform

import input.tfplan as tfplan

deny[reason] {
  rc := tfplan.resource_changes[_]
  rc.type == "random_pet"
  rc.change.after.length < 2
  reason := sprintf(
    "%s: random_pet length should be >= 2 for readable names (got %d)",
    [rc.address, rc.change.after.length],
  )
}
