# Required tags — keys, values, and provider mapping

This file is loaded on demand via `read_skill_file` — it is the detail behind
the summary in `SKILL.md`, kept out of the system prompt until it is needed.

## Required keys

| Key          | Required   | Allowed values / format                  |
|--------------|------------|------------------------------------------|
| `cost-center`| yes        | 4-digit code, e.g. `4821`                |
| `owner`      | yes        | team email, e.g. `platform@example.com`  |
| `env`        | yes        | `dev` \| `staging` \| `prod`             |
| `managed-by` | yes        | always `turf`                            |
| `data-class` | if data    | `public` \| `internal` \| `confidential` |

## Naming pattern

`<env>-<app>-<resource>`, lowercase, hyphen-separated.

- `prod-web-bucket`
- `staging-api-redis`
- `dev-data-postgres`

Keep names stable: renaming a resource is a destroy-and-recreate (`±`) for most
providers, so settle on the name before the first apply.

## Provider tag-key mapping

The same key/value set, placed under each provider's convention:

| Provider             | Where tags go                          |
|----------------------|----------------------------------------|
| `aws`                | `tags = { ... }`                       |
| `azurerm`            | `tags = { ... }`                       |
| `google`             | `labels = { ... }` (Google calls them labels) |
| `azapi`              | `tags` property inside `body`          |
| `kubernetes`         | `metadata.labels` (use dots, not hyphens, in label keys) |

Only the container key differs; the values are identical everywhere. For
Kubernetes labels, convert hyphenated keys to dotted equivalents
(`cost-center` → `cost-center` is fine as a label *value* but as a *key* use
`cost-center` only if it is a valid label name; otherwise namespace it, e.g.
`example.com/cost-center`).
