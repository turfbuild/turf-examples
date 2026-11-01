# Replace & teardown ordering

A minimal, credential-free example (the `random` provider only) that demonstrates
how Turf orders a **replacement** of a dependent and its dependencies — matching
Terraform/OpenTofu semantics.

`random_pet.server` references `random_integer.port` and `random_password.secret`
through its `keepers`, so `server` **depends on** both. When all three are
replaced, the old objects must be torn down in reverse-dependency order: **the old
port and secret must not be destroyed until the old server has been destroyed.**

## Usage

Create the three resources:

```bash
turf -C terraform/language/replace-ordering up
```

Then force-replace all three through the MCP tools, and read the order from the round's
plan document and from the apply:

```text
init({ path: "terraform/language/replace-ordering" })
open({})
up({})
# → awaiting_plan: round 1's plan gate, where the round's options are given
plan({ convergence_id: "<from up>", replace: ["random_integer.port", "random_password.secret", "random_pet.server"] })
# → awaiting_approval: plan.uri is the round's plan, as `tofu show -json` prints it (show reads it)
apply({ convergence_id: "<from up>", plan_digest: "<plan.digest>" })
```

## Scenario A — delete-then-create (the default config)

With no `lifecycle` block every replacement is **delete-then-create** (`∓`). The
execution order:

<!-- TODO(v1 re-run): re-derive this from a real v1 run: the plan document (`show`, plan.uri: each replace's action order and create_before_destroy) and the round's results -->
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
**infectious-CBD** rule: a CBD dependent forces its replaced dependencies to CBD
too, otherwise the mixed pair would form a destroy-order cycle
(`port.create → port.delete → server.delete → server.create → port.create`).

All three apply as `±`, and the new objects lead:

<!-- TODO(v1 re-run): re-derive this from a real v1 run: the plan document (`show`, plan.uri: each replace's action order and create_before_destroy) and the round's results -->
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

<!-- TODO(v1 re-run): confirm against the plan document (`show`, plan.uri) whether it already shows port/secret as create-before-destroy, and rewrite this note to match -->
Turf finalized the forced-CBD ordering when the plan was approved, not when it was
first planned, so the plan shown before approval listed `port`/`secret` as plain
delete-then-create and the forced `±` ordering appeared only once the round was
approved. Terraform bakes the same flip into the plan during graph construction
(its plan is atomic, so it has no equivalent intermediate view). The approved plan
and the execution agree.
