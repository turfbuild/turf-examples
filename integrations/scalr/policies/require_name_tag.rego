# Require a Name tag on every taggable AWS resource — a classic governance rule,
# in modern rego (v1 / OPA 1.0+) so the same file evaluates in Scalr's engine and
# locally via an OPA MCP server (`rego_eval`). Package MUST be `terraform`; the
# rule MUST produce a `deny` set of strings (Scalr's contract). The plan arrives at
# `input.tfplan` (the standard `tofu show -json` document).
#
# This gates the variable→module demo: the terraform-aws-modules/vpc plan is
# checked at plan-approval, inside the LOCAL turf session, via the OPA MCP server —
# governance at the decision point, not a remote Scalr run.
package terraform

import rego.v1

# Resources being created/updated whose provider schema carries a `tags` attribute.
taggable_changes contains rc if {
	some rc in input.tfplan.resource_changes
	rc.change.after.tags != null
}

deny contains reason if {
	some rc in taggable_changes
	not rc.change.after.tags.Name
	reason := sprintf("%s is missing the required tag \"Name\"", [rc.address])
}
