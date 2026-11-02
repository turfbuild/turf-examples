# Deploying with guardrails

Three guardrails, in the order they bite, around one small stack (a kind
cluster and podinfo in it):

1. **Every provider is scanned before it runs.** `init` installs the
   providers and reports each one's `package_dir` and `hashes`; the scan reads
   those directories; a blocking verdict stops the session before
   `open`, so the binary never executes.
2. **The configuration you deploy is pinned.** The workload is a module at a
   **commit** of this repository (`git::…//terraform/modules/podinfo?ref=…`),
   so what runs is exactly what was reviewed, and an upgrade is a ref bump —
   a diff to read.
3. **Every plan is checked against policy before it is approved.** `plan`
   leaves each round's plan waiting at its approval point (`plan.uri`,
   OpenTofu's JSON plan, which `show` reads) and nothing applies until its
   digest is named, so a policy tool reads the plan that gets approved.
   `policies/readable_pet_names.rego` is the rule.

And `guardrails.turf.hcl` makes the first and the third a step of the apply
itself, so a run nobody reviews (the agent approving its own plan, or a planfile
applied elsewhere) cannot skip them.

## What this demonstrates

- **Scan what `init` installed.** For each entry in `init`'s `providers[]`:
  `trivy rootfs --scanners vuln,secret <package_dir>` or `grype dir:<package_dir>`
  (or the Grype MCP server). Present the verdicts. A CRITICAL finding, or an
  unknown signature, means stop: do not open the workspace. `init` also wrote
  `.terraform.lock.hcl`; the engine refuses a provider whose hash no longer
  matches it.
- **Pin what you deploy.** `module "app"`'s `source` names a ref; `init`
  fetched that commit and nothing else. Bump the ref and `init({ upgrade: true })`
  to move it; the next plan is the diff. (`oci://` module sources work the same
  way, anonymous pulls.) The configuration directory itself is still local —
  a remote *root* is not something Turf does yet.
- **Policy at the approval point.** `up` with the default `length = 1`, then
  `plan`: `opa eval -i <file> -d policies/ 'data.terraform.deny'` on `show`'s
  document written to a file (or `conftest`, or the OPA MCP server) returns a
  denial — decline it (`apply({ convergence_id, decline: true, reason })`). `up({ var:
  { length: 2 } })`, then `plan`, returns none — approve by the digest of the
  plan that was checked. A plan that changed since is refused.
- **The guardrails ride with the configuration.** `guardrails.turf.hcl` — tofu
  and terraform ignore it by its name; Turf lays it over `main.tf` at every
  plan — binds two `turf_action`s `before_create` on the first resource the
  plan creates, with `halt`: `attest` (the agent stands behind the scan it
  ran: every provider, by directory, none blocked) and `check` (the same rego,
  against the values about to be created). A `turf_action` is the built-in
  action the agent driving Turf carries out itself: the apply stops at
  `awaiting_actions`, the agent does the step, and answers with
  `apply(action_results)`. Two steps on one caller pause the apply one at a
  time, in the order written: `attest`, then `check`. A failure at either
  stops the pet and podinfo, which is named after it; the cluster, which
  depends on neither, still applies.
- **Then two rounds.** The cluster in round one; podinfo, whose provider was
  unknown until the cluster existed, in round two.

Through a TACO, the policy half is the same check with the policy group read
from the control plane: see
[`integrations/scalr`](../../integrations/scalr/README.md).

## Prerequisites

- **Turf** (the Turf CLI or any MCP client pointed at `turf-mcp-server`; see
  [Running the examples](../../README.md#running-the-examples)).
- **A scanner**: `trivy` or `grype` on the `PATH`, or the Grype MCP server
  (`.turf/turf.yaml` wires it for the Turf CLI, Docker required).
- **A policy engine**: `opa` or `conftest` on the `PATH`, or the OPA MCP server
  (same file).
- **Docker** for the kind cluster. `git` on the engine's `PATH` for the pinned
  module.

## Usage

```bash
turf -C use-cases/guardrails up
```

In the session: scan after `init`, before the workspace; evaluate the plan
before approving; expect the apply to stop twice — `attest`, then `check` —
before anything is created.

## Cleanup

```bash
turf -C use-cases/guardrails destroy     # or kind delete cluster --name turf-guardrails
```
