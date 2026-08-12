# turf-cli/ — configuring the Turf CLI (`.turf/`)

How the standalone [Turf CLI](https://github.com/turfbuild/turf) is configured
per project, from its `.turf/` directory: **user skills** (`.turf/skills/`) and
**model configuration** (`.turf/turf.yaml`), including *First Available Models*.

Run the CLI from here and it picks up both:

```sh
cd integrations/turf-cli
turf chat
```

Everything under `.turf/` that is *source* (skills, `turf.yaml`) is committed;
the CLI's machine-local state (session/memory dbs) is git-ignored — see
[`.gitignore`](.gitignore).

---

## Model configuration: `.turf/turf.yaml`

A turf-owned overlay file. turf keeps its agent (persona, MCP tools, safety
gates) in code and reads only the sections you configure — today, models. Values
under `models:`/`providers:` use the same schema Docker's docs document, so
`first_available:`, named models, and tuning fields all work as written.

turf merges two locations, **project overriding global**:

```
~/.turf/turf.yaml            # global — your personal defaults, every project
./.turf/turf.yaml            # project — versioned with the infra config (this dir)
```

### Precedence

```
--model / TURF_MODEL   >   turf.yaml `model:`   >   built-in default (auto)
```

- `--model` accepts a **named model** from `turf.yaml` (`--model fast`), an inline
  **`provider/model`** (`--model anthropic/claude-sonnet-5`), or **`auto`**.
- A **local model must be a named entry**, not an inline ref: it needs
  `provider_opts.context_size` (turf's prompt is ~27k tokens, far past Docker
  Model Runner's default window), and an inline `provider/model` carries no
  per-model options.
- `auto` (the default when nothing is set) picks the first provider whose
  credentials are present — zero-config "first available".
- Env wins over the file, so `unset TURF_MODEL` if you want this directory's
  `turf.yaml model:` to take effect.

### The active config here

[`.turf/turf.yaml`](.turf/turf.yaml) defines a `default` model with a
`first_available` list (Anthropic → Google → local `dmr`), so `turf chat` here
works with whatever credentials you have — set a key for any one candidate.

### Gallery — copy one to `.turf/turf.yaml`

| File | Setup |
|------|-------|
| [`gallery/first-available.turf.yaml`](gallery/first-available.turf.yaml) | Credential-based fallback across several providers, keyless local last. |
| [`gallery/named-models.turf.yaml`](gallery/named-models.turf.yaml) | A `smart`/`fast`/`local` catalog with tuning; switch via `--model` or `/model`. |
| [`gallery/local-only.turf.yaml`](gallery/local-only.turf.yaml) | Fully local, keyless, offline via Docker Model Runner — including the `context_size` a local model needs. |
| [`gallery/openai-compatible.turf.yaml`](gallery/openai-compatible.turf.yaml) | A custom OpenAI-compatible endpoint (vLLM / LM Studio / gateway) via `providers:`. |
| [`gallery/models-gateway.turf.yaml`](gallery/models-gateway.turf.yaml) | Route every model through a gateway that supplies credentials. |

```sh
cp gallery/named-models.turf.yaml .turf/turf.yaml
turf --model fast chat
```

### The `/model` picker (full TUI)

In the full TUI, `/model` lists your named models plus locally-pulled Docker
Model Runner models and the models.dev catalog filtered by the credentials you
have, and switches the model for the current session. The switch is
session-scoped — `turf.yaml` remains the persistent default. (The `--lean` TUI
has no slash commands, so `/model` is full-TUI only.)

---

## Project skill: `.turf/skills/tagging-policy/`

`turf` discovers user skills from turf-owned locations only — the working dir's
`.turf/skills/` and the global `~/.turf/skills/` — never `~/.claude`, `~/.codex`,
or `~/.agents`. Launch `turf` here and the agent gains a `tagging-policy` skill
(loadable with `read_skill`) on top of the Turf MCP server's built-in `skill_*`
workflows.

```
.turf/skills/
  tagging-policy/
    SKILL.md             # name/description frontmatter + when-to-use + steps
    references/
      tags.md            # loaded on demand via read_skill_file
```

The recommended layout is one directory per skill with a lean `SKILL.md` and the
detail pushed into `references/*.md`, loaded only when needed. Drop more skills into
`.turf/skills/<name>/`, or into `~/.turf/skills/<name>/` for skills you want in every
project.
