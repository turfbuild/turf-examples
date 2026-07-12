# turf-cli/ — Turf CLI skill discovery

A demonstration of how the standalone [Turf CLI](https://github.com/turfbuild/turf)
discovers user skills. This directory holds **only** a demo skill — no scratch state,
no working files.

Run the CLI from here:

```sh
cd integrations/turf-cli
turf chat
```

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
