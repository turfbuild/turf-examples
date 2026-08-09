# Turf, tailored for Scalr

[Scalr](https://scalr.io) is a Terraform control plane and remote state backend. This
integration runs **Turf as the engine and Scalr as the control plane**: Turf plans and
applies locally while Scalr holds the variables and defines policy. The Scalr side is
provisioned as code with the Scalr Terraform provider.

## What's here

| Path | What it shows |
|------|---------------|
| [`setup/`](setup)       | Provisions the Scalr side with the `scalr` provider — an environment, a state-storage-only workspace, a `region` variable, a published module, and (optionally) an OPA **policy group**. Apply this first. |
| [`chat/`](chat)         | The **headline** demo — one local session pulls a Scalr workspace variable into a registry module and gates the plan on the Scalr OPA policy group, via the `scalr` + `opa` MCP servers. Governance composed locally, no Scalr run. |
| [`policies/`](policies) | The OPA guardrails (rego v1) — `scalr-policy.hcl` + the `.rego` files. They are both the policy group's source (synced by `setup/`) and the local gate's rules (evaluated by `chat/`). |

## Prerequisites

- A Scalr account (`<acct>.scalr.io`) and the Turf CLI (or any MCP client on
  `turf-mcp-server`).
- A Scalr token for the **`scalr` provider** (`setup/`): `SCALR_TOKEN` (local runs also
  want `SCALR_ACCOUNT_ID` or the `scalr_account_id` tfvar).

## Run order

```bash
# 1. Provision the Scalr side. Add -var enable_policy_group=true for chat/'s gate.
export SCALR_TOKEN="…"  SCALR_ACCOUNT_ID="acc-…"
cd integrations/scalr/setup && cp terraform.tfvars.example terraform.tfvars   # fill in scalr_hostname
turf -C integrations/scalr/setup up

# 2. The interactive demo — see chat/README.md for the session prompts.
export SCALR_API_TOKEN="$SCALR_TOKEN"  SCALR_API_URL="https://example.scalr.io"
turf -C integrations/scalr/chat --allow-path ../policies up
```

Tear down with `turf -C integrations/scalr/setup destroy`.

## References

- Scalr CLI / remote backend — https://docs.scalr.io/docs/cli
- Private module registry — https://docs.scalr.io/docs/private-module-registry
- OPA policy as code — https://docs.scalr.io/docs/policy-as-code
- Scalr Terraform provider — https://registry.terraform.io/providers/Scalr/scalr/latest/docs
