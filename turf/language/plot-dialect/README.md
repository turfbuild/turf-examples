# Plot dialect — ad-hoc authoring, then graduate

**Dialect: plot.** Every other `terraform/<...>` example in this repo is a **tofu**
configuration — plain hand-authored `.tf` files. This one is a **plot**: a directory
of `*.tfplot.hcl` units authored by Turf's `declare_*` tools. It shows the ad-hoc end
of the spectrum and how a plot **graduates** into a tofu configuration with
`config_promote`.

Entirely local and credential-free (the `random` provider — no cloud account).

## What This Demonstrates

Turf spans a spectrum: natural-language → ad-hoc → codified HCL. The **configuration
directory** is the durable identity at every point on it. When you start from an empty
directory, the `declare_*` tools populate it with **plot units** — one `*.tfplot.hcl`
file per address, each pairing a `turf { }` metadata block (a human-readable `intent`
plus that unit's `required_providers`) with exactly one verbatim Terraform block. The
plan is always a projection of this directory; check it into git and reopen it later.

When the plot has stabilized, `config_promote` turns it into an ordinary tofu
configuration — a **strip-fold-rename**: strip each `turf { }` block (its `intent`
becomes a leading `#` comment), fold every unit's `required_providers` into one
`versions.tf`, and rename each `<address>.tfplot.hcl` to `<address>.tf`. The result is
walk-equivalent, so a fresh plan is all-NoOp.

## The Units

| File | Address | Intent |
|------|---------|--------|
| `main.tfplot.hcl`             | *(settings)* | plot name, version, and the declared `backend "local"` |
| `random_pet.name.tfplot.hcl`  | `random_pet.name` | the base pet name |
| `random_string.suffix.tfplot.hcl` | `random_string.suffix` | a short random suffix |
| `output.full_name.tfplot.hcl` | `output.full_name` | the assembled `pet-suffix` name |

The module-level `required_providers` is **folded** from each unit's
`turf { required_providers }` at plan time — it is never written into a unit by hand.

## How It Was Authored (the declare family)

A plot like this is produced by an agent (or you, via the MCP tools), not typed by
hand. The equivalent tool calls:

```
config_init(path: "turf/language/plot-dialect")   # empty dir → plot dialect
declare_backend(type: "local", config: { path: "terraform.tfstate" })
workspace_open(backend_type: "local", ...)             # you carry the backend args
provider_load(name: "random", source: "hashicorp/random", version: "~> 3.0")
plan_new()                                              # initial walk
declare_resource(resource_addr: "random_pet.name",     type: "random_pet",    config: { length: 2 })
declare_resource(resource_addr: "random_string.suffix", type: "random_string", config: { length: 4, special: false, upper: false })
declare_outputs(outputs: { full_name: "${random_pet.name.id}-${random_string.suffix.result}" })
plan_approve(); effect_apply(...)                       # converge
```

Each `declare_*` call writes/updates one `*.tfplot.hcl` unit **and** folds the change
into the open plan.

## Usage

Drive it with the Turf CLI — its initial walk plans the whole plot:

```bash
turf -C turf/language/plot-dialect up
```

Or with the MCP tools directly: `config_init` against the directory (it reports
`dialect: plot`), then `plan_new`.

## Graduate to a tofu configuration

Once the plot is applied and stable, promote it (one-way):

```
config_promote()          # plot → tofu, in place
```

The directory is rewritten to classic `.tf` files:

- `versions.tf` — the folded `terraform { backend "local"; required_providers { random } }`.
- `random_pet.name.tf`, `random_string.suffix.tf`, `output.full_name.tf` — the same
  Terraform blocks, each led by its former `intent` as a `#` comment.

After promotion the directory's dialect is **tofu**: the `declare_*` tools now refuse
it (edit the `.tf` files and `replan`), and a fresh `plan_new` is all-NoOp — the
promotion is walk-equivalent. `config_promote` requires the plot to be fully applied
first (pass `force: true` to override).

## Cleanup

```bash
turf -C turf/language/plot-dialect destroy
```

The `random` resources live only in local state; destroy removes them. The plot units
(or, after promotion, the `.tf` files) remain — they are the durable configuration.
