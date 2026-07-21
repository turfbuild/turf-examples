# Local module — a portable plot that calls `./modules/greeting`

**Dialect: plot.** A directory of `*.tfplot.hcl` units authored by Turf's `declare_*`
tools (see [`../plot-dialect`](../plot-dialect) for the dialect itself). This one adds
a **local module call**: `module.greeting` sourced from `./modules/greeting`, a path
relative to *this* configuration directory.

Entirely local and credential-free (the `random` provider — no cloud account).

## What This Demonstrates

Terraform resolves a local module `source` against the directory of the config that
references it. Turf does the same for a plot — and, crucially, **stores the `source`
verbatim** in the unit:

```hcl
# module.greeting.tfplot.hcl
module "greeting" {
  source = "./modules/greeting"   # relative — no absolute path is baked in
  prefix = "hello"
}
```

Because the relative path is preserved (not rewritten to an absolute one), the whole
directory is **portable**: commit it to git, clone it on another machine, and
`module.greeting` still resolves to the sibling `modules/greeting/` — the plan is
unchanged. The layout that travels together:

```
local-module/
  main.tfplot.hcl              # plot settings (name, backend)
  module.greeting.tfplot.hcl   # the module call — source = "./modules/greeting"
  modules/greeting/main.tf     # the local module (a prefixed random_pet + output)
```

## The Units

| File | Address | Intent |
|------|---------|--------|
| `main.tfplot.hcl`             | *(settings)*      | plot name, version, and the declared `backend "local"` |
| `module.greeting.tfplot.hcl`  | `module.greeting` | calls the local `./modules/greeting` module with `prefix = "hello"` |

The module's own `required_providers` (here `random`) is folded into the plot's
module-level `required_providers` at plan time — you never write that block by hand.

## How It Was Authored (the declare family)

A plot like this is produced by an agent (or you, via the MCP tools), not typed by
hand. The module call is one `declare_module` with a relative `source`:

```
config_init(path: "turf/language/local-module")       # empty dir → plot dialect
workspace_open(backend_type: "local", ...)
provider_load(name: "random", source: "hashicorp/random", version: "~> 3.0")
plan_new()                                             # initial walk
declare_module(address: "module.greeting", source: "./modules/greeting", inputs: { prefix: "hello" })
plan_approve(); effect_apply(...)                      # converge
```

`declare_module` writes `module.greeting.tfplot.hcl` with the `source` **exactly as you
passed it** (`./modules/greeting`), installs the module, and folds the call into the
open plan. (Register the module directory next to the plot first — the `modules/greeting/`
tree here.)

## Usage

```bash
turf -C turf/language/local-module up
```

Or with the MCP tools directly: `config_init` against the directory (it reports
`dialect: plot` and installs the local module), then `plan_new`.

## Graduate to a tofu configuration

```
config_promote()          # plot → tofu, in place
```

The units become classic `.tf` files (`module.greeting.tf` + a folded `versions.tf`),
and the module `source` stays `./modules/greeting` — the promoted configuration is just
as portable, and a fresh `plan_new` is all-NoOp.

## Cleanup

```bash
turf -C turf/language/local-module destroy
```

The `random_pet` inside the module lives only in local state; destroy removes it. The
plot units and `modules/greeting/` remain — they are the durable configuration.
