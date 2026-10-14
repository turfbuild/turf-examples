# Azure AVM resource group — multi-instance (keys & counts)

This example deploys **several** Azure resource groups from the published
[`Azure/avm-res-resources-resourcegroup/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm)
module: `main.tf` puts `for_each` on the `module` block (native HCL), and Turf's plan expands
it into native keyed addresses — `module.resource_group["eastus"]`, `module.resource_group["westus"]`.

> Requires Azure credentials for the `azurerm` provider, so this is a showcase rather than a
> CI-runnable config. The provider runs in Turf's engine and reads them from its environment:
> the `az` login, or `ARM_*` variables in `turf.env` or the configuration's `mise.local.toml`
> (see [Running the examples](../../../README.md#running-the-examples)).

## Plan it (`up`)

`main.tf` declares `var.resource_groups` (a map keyed by region) and a single `module "resource_group"`
with `for_each = var.resource_groups`. `up` plans the directory and expands it:

```
init({ path: "terraform/azure/avm-resourcegroup" })   # installs the module and every provider
open({})
up({})
→ module.resource_group["eastus"].azurerm_resource_group.this   + create
  module.resource_group["westus"].azurerm_resource_group.this   + create
```

`init` installs what the **root** module requires — here only `azurerm`, whose `provider {}`
block in `main.tf` configures it — and what the module calls require too: the AVM module's
`azapi`, `modtm` and `random`, with the module's own constraints. Its `providers[]` lists all
four, as `tofu init` installs them. `main.tf` pins the module to 0.2.x: from 0.3.0 it moves its
resources to `azapi_resource` with `moved` blocks that change a resource's type, which Turf
refuses.

`up` stops at its approval point with the plan; `apply` with its `plan_digest` applies it. Add or
drop a region in `var.resource_groups` and only that instance is created/deleted; the others
stay `noop`.

### `count` instead of `for_each`

When the instances are homogeneous, `count` works too (int-keyed addresses
`module.resource_group_n[0]`, `[1]`, referencing `count.index`). `main.tf` carries a commented-out
`module "resource_group_n"` that shows the shape; uncomment it (and its `rg_count` variable),
re-run `init` (a new `module` block needs installing, as with `tofu init`), and
`up` again to compare. `count` and `for_each` are mutually exclusive on one `module` block.

### Day-2: shrink and destroy

Shrinking and removing are edits to the files, followed by another `up`:

- **Shrink** — remove a key from `var.resource_groups`; the dropped instance is detected as an orphan
  and planned `-` (delete), the rest stay `noop`.
- **Remove** — delete the `module "resource_group"` block; the next plan tears down every keyed
  instance (reverse-topological). To stop managing them *without* destroying anything, replace the
  block with a `removed` block instead:

  ```hcl
  removed {
    from = module.resource_group
    lifecycle {
      destroy = false
    }
  }
  ```

- **Tear down everything, keep the configuration** — `destroy({})`, then `apply` its plan.
