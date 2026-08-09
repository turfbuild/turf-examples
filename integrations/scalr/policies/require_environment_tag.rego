# Require an `Environment` tag on every taggable AWS resource. Unlike a `Name` tag —
# which well-behaved modules (e.g. terraform-aws-modules/vpc) inject on their own, so
# a "require Name" rule can never fire on them — `Environment` is NOT auto-provided by
# the module. That makes this a policy a real module plan actually fails, and the
# remedy is a single module input: `tags = { Environment = "..." }`, which the module
# merges into every resource.
#
# Modern rego (v1 / OPA 1.0+) so the same file evaluates in Scalr's engine and locally
# via the OPA MCP server (`rego_eval`). Package MUST be `terraform`; the rule MUST
# produce a `deny` set of strings (Scalr's contract). The plan arrives at
# `input.tfplan` (the standard `tofu show -json` document).
#
# This gates the variable→module demo at plan-approval, inside the LOCAL turf session,
# via the OPA MCP server — governance at the decision point, not a remote Scalr run.
package terraform

import rego.v1

# Resources being created/updated whose provider schema carries a `tags` attribute.
taggable_changes contains rc if {
	some rc in input.tfplan.resource_changes
	rc.change.after.tags != null
}

deny contains reason if {
	some rc in taggable_changes
	not rc.change.after.tags.Environment
	reason := sprintf("%s is missing the required tag \"Environment\"", [rc.address])
}
