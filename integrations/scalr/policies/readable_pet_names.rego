# A tiny OPA policy for Scalr, in modern rego (v1 / OPA 1.0+) syntax so the same
# file evaluates both in Scalr's engine and locally via an OPA MCP server
# (`rego_eval`). The package MUST be named `terraform` and the rule MUST produce a
# `deny` set of human-readable strings — that is Scalr's OPA contract. The plan is
# provided at `input.tfplan` (the standard `tofu show -json` document).
#
# This one is advisory (see scalr-policy.hcl): it encourages `random_pet` names to
# keep length >= 2 so generated identifiers stay readable. It is deliberately keyed
# to the random workload the examples create, so a policy check evaluates against a
# real plan.
package terraform

import rego.v1

deny contains reason if {
	some rc in input.tfplan.resource_changes
	rc.type == "random_pet"
	rc.change.after.length < 2
	reason := sprintf(
		"%s: random_pet length should be >= 2 for readable names (got %d)",
		[rc.address, rc.change.after.length],
	)
}
