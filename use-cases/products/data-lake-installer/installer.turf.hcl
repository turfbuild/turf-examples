# The installer's own steps: what the product wants checked, said and asked
# around its reference architecture, as Turf actions. tofu and terraform
# ignore this file by its name; Turf lays it over lake.tf at every plan, and
# these steps stop the apply even when it runs unattended (the agent approving
# its own plan, or a planfile applied elsewhere) — an installer that runs by
# itself, governed by what its author wrote here.
#
# A turf_action is the built-in action the agent driving Turf carries out
# itself: the apply stops at awaiting_actions with the prompt and inputs, the
# agent does the step with its own tools, and answers with
# apply(action_results).

# Verify: after each bucket exists, confirm nothing public can reach it. A
# failure taints the bucket, so the next up replaces it.
action "turf_action" "verify_private" {
  config {
    prompt = <<-EOT
      Confirm bucket ${caller.bucket} blocks public access: with the AWS CLI
      (or the AWS MCP tools if you have them), read its public access block
      and fail unless all four settings are true. Report what you read.
    EOT
    inputs = { bucket = caller.bucket, arn = caller.arn, region = var.region }
  }
}

action_trigger "verify_private" {
  target     = aws_s3_bucket.raw
  events     = [after_create]
  actions    = [action.turf_action.verify_private]
  on_failure = taint
}

action_trigger "verify_private_curated" {
  target     = aws_s3_bucket.curated
  events     = [after_create]
  actions    = [action.turf_action.verify_private]
  on_failure = taint
}

# Announce: once the workgroup exists the lake is usable. Tell the customer;
# a failed notice only warns.
action "turf_action" "welcome" {
  config {
    prompt = <<-EOT
      The ${var.product_name} data lake for tenant ${var.tenant} is ready. Tell
      the customer in one short message — workgroup ${caller.name}, and that
      the bucket and catalog names are in the configuration's outputs — with
      your messaging tool if you have one; otherwise fail and say you have none.
    EOT
    inputs = { workgroup = caller.name, tenant = var.tenant }
  }
}

action_trigger "welcome" {
  target     = aws_athena_workgroup.lake
  events     = [after_create]
  actions    = [action.turf_action.welcome]
  on_failure = continue
}

# Ask: the catalog is the customer's data. Nothing removes it without their
# word. Bound before_destroy, and declared so it can also be put to them on
# demand: invoke({ action_addr: "action.turf_action.consent" }).
action "turf_action" "consent" {
  config {
    prompt = <<-EOT
      Ask the customer whether the ${var.product_name} data catalog for tenant
      ${var.tenant} may be removed, and that they understand the lake's tables
      become unqueryable. Quote their answer in progress. Succeed only if they
      say yes; if they decline, fail with their reason.
    EOT
    inputs = { tenant = var.tenant }
  }
}

action_trigger "consent" {
  target     = aws_glue_catalog_database.lake
  events     = [before_destroy]
  actions    = [action.turf_action.consent]
  on_failure = halt
}
