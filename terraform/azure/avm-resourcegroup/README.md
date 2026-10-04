# Azure AVM resource group — multi-instance (keys & counts)

This example deploys **several** Azure resource groups from the published
[`Azure/avm-res-resources-resourcegroup/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm)
module: `main.tf` puts `for_each` on the `module` block (native HCL), and Turf's walk expands
it into native keyed addresses — `module.resource_group["eastus"]`, `module.resource_group["westus"]`.

> Requires Azure credentials for the `azurerm` provider, so this is a showcase rather than a
> CI-runnable config.

## Plan it (`plan_new`)

`main.tf` declares `var.resource_groups` (a map keyed by region) and a single `module "resource_group"`
with `for_each = var.resource_groups`. Opening a phase plans the directory and expands it:

```
config_init({ path: "terraform/azure/avm-resourcegroup" })   # installs the registry module
workspace_open({ required_providers: {                       # the module's own providers
  azapi:  { source: "Azure/azapi",      version: "~> 2.4" },
  modtm:  { source: "azure/modtm",      version: "~> 0.3" },
  random: { source: "hashicorp/random", version: "~> 3.5" } } })
plan_new({})
→ module.resource_group["eastus"].azurerm_resource_group.this   + create
  module.resource_group["westus"].azurerm_resource_group.this   + create
```

`workspace_open` loads what the **root** module requires — here only `azurerm`, whose `provider {}`
block in `main.tf` configures it. The AVM module also requires `azapi`, `modtm` and `random`, and a
provider that only a child module requires has to be named in `workspace_open`'s
`required_providers` (or declared in the root's). Terraform needs neither; turf refuses the plan
until they are loaded, naming each one. `config_init`'s `required_providers` lists them, with the
module's constraints. `main.tf` pins the module to 0.2.x: from 0.3.0 it moves its resources to
`azapi_resource` with `moved` blocks that change a resource's type, which turf refuses.

Then `plan_approve({})` and `effect_apply` each ready effect, as usual. Add or drop a region in
`var.resource_groups` and only that instance is created/deleted; the others stay `noop`.

### `count` instead of `for_each`

When the instances are homogeneous, `count` works too (int-keyed addresses
`module.resource_group_n[0]`, `[1]`, referencing `count.index`). `main.tf` carries a commented-out
`module "resource_group_n"` that shows the shape; uncomment it (and its `rg_count` variable),
re-run `config_init` (a new `module` block needs installing — it is turf's `tofu init`), and
`replan` to compare. `count` and `for_each` are mutually exclusive on one `module` block.

### Day-2: shrink and destroy

Shrinking and removing are edits to the files, followed by `replan`:

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

- **Tear down everything, keep the configuration** — `plan_new({ destroy: true })`.
