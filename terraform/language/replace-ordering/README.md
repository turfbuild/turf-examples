# Replace & teardown ordering

A minimal, credential-free example (the `random` provider only) that demonstrates
how Turf's effect compiler orders a **replacement** of a dependent and its
dependencies — matching Terraform/OpenTofu semantics.

`random_pet.server` references `random_integer.port` and `random_password.secret`
through its `keepers`, so `server` **depends on** both. When all three are
replaced, the old objects must be torn down in reverse-dependency order: **the old
port and secret must not be destroyed until the old server has been destroyed.**

## Usage

Create the three resources:

```bash
turf -C terraform/language/replace-ordering up
```

Then force-replace all three and inspect the compiled DAG via the MCP tools:

```text
plan_new({ replace: ["random_integer.port", "random_password.secret", "random_pet.server"] })
config_plan({ path: "terraform/language/replace-ordering" })
plan_approve({})
# read turf://workspaces/default/phases/<id>/execution?state=all
```

## Scenario A — delete-then-create (the default config)

With no `lifecycle` block every replacement is **delete-then-create** (`∓`). The
compiled execution:

```
∓/random_pet.server/delete        deps: []                          ← ready (leads)
∓/random_integer.port/delete      deps: [server/delete]             ← old port waits on old server
∓/random_password.secret/delete   deps: [server/delete]             ← old secret waits on old server
∓/random_integer.port/create      deps: [port/delete]               (replace mate)
∓/random_password.secret/create   deps: [secret/delete]             (replace mate)
∓/random_pet.server/create        deps: [server/delete, port/create, secret/create]
```

Apply order:

```
server.delete → {port.delete, secret.delete} → {port.create, secret.create} → server.create
   (old)            (old, only after server)        (new)                         (new)
```

The old port is destroyed **only after** the old server — the dependent is torn
down before its dependencies.

## Scenario B — forced create-before-destroy (uncomment the `lifecycle` block)

Set `create_before_destroy = true` on `server` only. `server` is now CBD (`±`),
but `port`/`secret` are still plain in config. Turf applies Terraform's
**infectious-CBD** rule at seal: a CBD dependent forces its replaced dependencies
to CBD too, otherwise the mixed pair would form a destroy-order cycle
(`port.create → port.delete → server.delete → server.create → port.create`).

All three compile as `±`, and the new objects lead:

```
±/random_integer.port/create     deps: []                          ← ready (new before old)
±/random_password.secret/create  deps: []                          ← ready
±/random_pet.server/create       deps: [port/create, secret/create]
±/random_pet.server/delete       deps: [server/create]             (CBD mate)
±/random_integer.port/delete     deps: [port/create, server/delete]
±/random_password.secret/delete  deps: [secret/create, server/delete]
```

Apply order:

```
{port.create, secret.create} → server.create → server.delete → {port.delete, secret.delete}
   (new, deposing old)           (new)           (old)           (old, after old server)
```

### Note: where the CBD flip happens

Turf finalizes the forced-CBD ordering **at seal** (`plan_approve`), not during
the per-resource `config_plan` walk. So a `config_plan`/plan projection on the
*draft* shows `port`/`secret` as plain delete-then-create; the forced `±` ordering
appears once the phase is approved and compiled. Terraform bakes the same flip
into the plan during graph construction (its plan is atomic, so it has no
equivalent intermediate view). The *sealed* plan and the execution agree.
