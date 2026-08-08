# Scalr remote backend — conversational plot

The **conversational** twin of [`../state-backend`](../state-backend): the same
credential-free `random` workload, but authored ad-hoc as **plot units**
(`*.tfplot.hcl`) by Turf's `declare_*` tools — and backed by the **Scalr remote
backend**, so state + outputs land in the `turf-scalr-plot` workspace.

**Dialect: plot.** One `<address>.tfplot.hcl` file per address, each pairing a
`turf { }` metadata block (a human-readable `intent` plus that unit's
`required_providers`) with exactly one verbatim Terraform block. The settings unit
`main.tfplot.hcl` carries the `plot { }` block — including the `backend "remote"`
pointed at Scalr. See [`turf/language/plot-dialect`](../../../turf/language/plot-dialect)
for the dialect in full (and `config_promote` to graduate a plot to `.tf`).

## The Units

| File | Address | Intent |
|------|---------|--------|
| `main.tfplot.hcl`                 | *(settings)* | plot name/version + the `backend "remote"` → Scalr |
| `random_pet.name.tfplot.hcl`      | `random_pet.name` | the base pet name |
| `random_string.suffix.tfplot.hcl` | `random_string.suffix` | a short random suffix |
| `output.full_name.tfplot.hcl`     | `output.full_name` | the assembled `pet-suffix` name |

## How It Was Authored (the declare family)

A plot is produced by an agent (or you, via the MCP tools), not typed by hand. The
equivalent calls — note `declare_backend` carries the Scalr coordinates:

```
config_init(path: "integrations/scalr/plot")             # empty dir → plot dialect
declare_backend(type: "remote", config: {
  hostname     = "example.scalr.io",
  organization = "turf-demo",
  workspaces   = { name = "turf-scalr-plot" }
})
workspace_open(backend_type: "remote", ...)
provider_load(name: "random", source: "hashicorp/random", version: "~> 3.0")
declare_resource(resource_addr: "random_pet.name",      type: "random_pet",    config: { length: 2 })
declare_resource(resource_addr: "random_string.suffix", type: "random_string", config: { length: 4, special: false, upper: false })
declare_outputs(outputs: { full_name: "${random_pet.name.id}-${random_string.suffix.result}" })
plan_approve(); effect_apply(...)
```

## Prerequisites

Same as the coded example: the Scalr environment + workspaces from
[`../setup`](../setup), the `hostname` in `main.tfplot.hcl` edited to your account,
and a Scalr token (`terraform login <acct>.scalr.io`).

## Usage

```bash
turf -C integrations/scalr/plot up
```

Or with the MCP tools directly: `config_init` against the directory (it reports
`dialect: plot`), then `plan_new`.

> **Interop note:** a plot is turf-only dialect, so it's driven by `turf`, not `tofu`.
> `turf up` opens the Scalr `remote` backend directly and persists state in the
> `turf-scalr-plot` workspace (state, locks, version history live there; turf still
> plans/applies locally). See the [integration README](../README.md#interop-notes).

## Verify

```bash
turf -C integrations/scalr/plot output
# full_name = "<pet>-<suffix>"
```

State now lives in the Scalr `turf-scalr-plot` workspace — confirm in the UI or read
`full_name` back with the [Scalr MCP server](../README.md#read-it-back-with-the-scalr-mcp-server).

## Cleanup

```bash
turf -C integrations/scalr/plot destroy
```

The `random` resources are removed; the plot units remain (they are the durable
configuration). To remove the workspace itself, tear down [`../setup`](../setup).
