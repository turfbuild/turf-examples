# Local module — a portable configuration that calls `./modules/greeting`

An ordinary Terraform configuration with one **local module call**: `module.greeting`
sourced from `./modules/greeting`, a path relative to *this* configuration directory.

Entirely local and credential-free (the `random` provider — no cloud account).

## What This Demonstrates

Terraform resolves a local module `source` against the directory of the configuration
that references it, and so does Turf. The `source` is a plain relative path in
`main.tf`, and Turf never rewrites it:

```hcl
# main.tf
module "greeting" {
  source = "./modules/greeting"   # relative — no absolute path is baked in
  prefix = "hello"
}
```

Because nothing absolute is recorded, the whole directory is **portable**: commit it to
git, clone it on another machine, and `module.greeting` still resolves to the sibling
`modules/greeting/`, so the plan is unchanged. The layout that travels together:

```
local-module/
  main.tf                      # required_providers, backend "local", the module call
  modules/greeting/main.tf     # the local module (a prefixed random_pet + output)
```

| File | Holds |
|------|-------|
| `main.tf`                  | `required_providers` (`random ~> 3.0`), `backend "local"`, and `module "greeting"` with `prefix = "hello"` |
| `modules/greeting/main.tf` | the module: `var.prefix` → a `random_pet` → `output "greeting"` |

## How an Agent Authors It

Turf has no authoring tools. An agent (or you) writes `main.tf` with ordinary file
tools, then plans the directory with Turf:

```
config_init(path: "turf/language/local-module")   # registers the directory (an absent one is created)
  …write modules/greeting/main.tf and main.tf…    # your own file tools
config_init(path: "turf/language/local-module")   # re-run after adding a module block — it is turf's
                                                  # `tofu init`, and installs ./modules/greeting
workspace_open()                                  # backend + required providers come from main.tf
plan_new()                                        # plans the whole directory: module.greeting.random_pet.name  + create
plan_approve(); effect_apply(...)                 # after you approve the plan
```

To change it, edit the files and `replan`. Every plan walks the whole directory, so a
different `prefix` in `main.tf` shows up as a replacement of the `random_pet`.

## Usage

```bash
turf -C turf/language/local-module up
```

Or with the MCP tools directly: `config_init` against the directory (it installs the
local module), `workspace_open`, then `plan_new`.

## Cleanup

```bash
turf -C turf/language/local-module destroy
```

The `random_pet` inside the module lives only in local state, and destroy removes it.
`main.tf` and `modules/greeting/` remain: they are the durable configuration.
