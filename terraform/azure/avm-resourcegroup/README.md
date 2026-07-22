# Azure AVM resource group — multi-instance (keys & counts)

This example deploys **several** Azure resource groups from the published
[`Azure/avm-res-resources-resourcegroup/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm)
module, the same outcome reached two ways:

- **Codified** — `main.tf` puts `for_each` on the `module` block (native HCL). Drive it with the
  codified workflow (`config_init` against this directory, then `plan_new`).
- **Ad-hoc** — the `declare_module` tool's own `for_each`/`count` **meta-args** produce the same keyed
  instances from a conversational request, with no hand-written HCL (the walkthrough below).

Both emit native keyed addresses — `module.resource_group["eastus"]`, `module.resource_group["westus"]`.

> Requires Azure credentials for the `azurerm` provider, so this is a showcase rather than a
> CI-runnable config. The keyed `declare_module` mechanics themselves are exercised offline against
> a local `random`-provider module in Turf's own test suite.

## Codified (`plan_new`)

`main.tf` declares `var.resource_groups` (a map keyed by region) and a single `module "resource_group"`
with `for_each = var.resource_groups`. Opening a phase plans the directory and expands it:

```
config_init({ path: "terraform/azure/avm-resourcegroup" })
# workspace_open + provider_configure from the discovery payload, then:
plan_new({})
→ module.resource_group["eastus"].azurerm_resource_group.this   + create
  module.resource_group["westus"].azurerm_resource_group.this   + create
```

Add or drop a region in `var.resource_groups` and only that instance is created/deleted; the others
stay `noop`.

## Ad-hoc (`declare_module` meta-args)

Same module, no hand-written HCL — pass `for_each` on the **unkeyed** address (the declaration
writes through into the configuration directory as a `.tf.json` file). `inputs` may reference
`${each.key}` / `${each.value...}`:

```jsonc
// (after workspace_open + provider_configure for azurerm)
plan_new({})
declare_module({
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
declare_module({
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

- **Shrink** — re-`declare_module` with a key removed from `for_each`; the dropped instance is detected as
  an orphan and planned `-` (delete), the rest stay `noop`.
- **Remove** — `declare_module({ address: "module.resource_group", remove: true })` un-declares the call
  and plans every keyed instance's teardown (reverse-topological). For a whole-workspace teardown that
  keeps the configuration, use `plan_new({ destroy: true })` instead.

See `skill_adhoc` ("Multiple instances") for the full reference.
