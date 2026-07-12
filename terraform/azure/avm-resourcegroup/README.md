# Azure AVM resource group — multi-instance (keys & counts)

This example deploys **several** Azure resource groups from the published
[`Azure/avm-res-resources-resourcegroup/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm)
module, the same outcome reached two ways:

- **Codified** — `main.tf` puts `for_each` on the `module` block (native HCL). Drive it with the
  codified workflow (`config_plan` against this directory).
- **Ad-hoc** — the `module_plan` tool's own `for_each`/`count` **meta-args** produce the same keyed
  instances from a conversational request, with no HCL on disk (the walkthrough below).

Both emit native keyed addresses — `module.resource_group["eastus"]`, `module.resource_group["westus"]`.

> Requires Azure credentials for the `azurerm` provider, so this is a showcase rather than a
> CI-runnable config. The keyed `module_plan` mechanics themselves are exercised offline against
> a local `random`-provider module in Turf's own test suite.

## Codified (`config_plan`)

`main.tf` declares `var.resource_groups` (a map keyed by region) and a single `module "resource_group"`
with `for_each = var.resource_groups`. Planning the directory expands it:

```
config_plan({ config_dir: "terraform/azure/avm-resourcegroup" })
→ module.resource_group["eastus"].azurerm_resource_group.this   + create
  module.resource_group["westus"].azurerm_resource_group.this   + create
```

Add or drop a region in `var.resource_groups` and only that instance is created/deleted; the others
stay `noop`.

## Ad-hoc (`module_plan` meta-args)

Same module, no HCL file — pass `for_each` on the **unkeyed** address. `inputs` may reference
`${each.key}` / `${each.value...}`:

```jsonc
// (after workspace_open + provider_configure for azurerm)
plan_new({})
module_plan({
  address: "module.resource_group",
  source:  "Azure/avm-res-resources-resourcegroup/azurerm",
  version: "~> 0.2",
  for_each: {
    eastus: { location: "East US" },
    westus: { location: "West US 2" }
  },
  inputs: {
    name:     "rg-avm-demo-${each.key}",
    location: "${each.value.location}"
  }
})
// → resources: module.resource_group["eastus"].azurerm_resource_group.this  (+)
//              module.resource_group["westus"].azurerm_resource_group.this  (+)
//   outputs keyed by instance: { eastus: {...}, westus: {...} }
```

Then `plan_approve({})` and `effect_apply` each ready effect, as usual.

### `count` instead of `for_each`

When the instances are homogeneous, use `count` (int-keyed addresses `module.resource_group[0]`, `[1]`)
and reference `${count.index}`:

```jsonc
module_plan({
  address: "module.resource_group",
  source:  "Azure/avm-res-resources-resourcegroup/azurerm",
  version: "~> 0.2",
  count:   2,
  inputs:  { name: "rg-avm-demo-${count.index}", location: "East US" }
})
```

`count` and `for_each` are mutually exclusive. Keep the `address` itself unkeyed (`module.resource_group`,
not `module.resource_group["eastus"]`) — the keys come from the meta-arg.

### Day-2: shrink and destroy

- **Shrink** — re-`module_plan` with a key removed from `for_each`; the dropped instance is detected as
  an orphan and planned `-` (delete), the rest stay `noop`.
- **Destroy** — `module_plan({ ..., for_each: {...}, destroy: true })` tears down every keyed instance
  (reverse-topological). Pass the same identity tuple, including the `for_each`/`count` meta-arg.

See `skill_adhoc` ("Multiple instances") for the full reference.
