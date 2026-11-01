# EVA

> A stable soul for your terminal agent, plus a library that opens on demand.

**EVA is a plugin for [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh) (`dsh`).** It replaces the default opener with a persona you control, and mounts a curated skill view instead of the whole library.

Installing it changes exactly two config rows and creates one directory. Uninstalling deletes them.

## Why

- **Persona drift** — every session starts with the same generic "You are an AI agent". EVA pins the identity in `personaPrefix`.
- **Context tax** — mounting 338 skills costs ~55K characters *per request*. EVA mounts a curated subset and keeps the rest behind an on-disk index.
- **Stay reversible** — no model, tool, or sandbox changes. Two rows in, two rows out.

## Quick start

```powershell
git clone https://github.com/<you>/EVA.git
cd EVA

.\scripts\install.ps1 -SkillsPack C:\path\to\skills-pack -Persona eva
dsh plugin --profile desktop add file:$PWD
# restart dsh
```

## How it works

| row id | field | effect |
|---|---|---|
| `system-prompt` | `personaPrefix`, `includeHarnessIdentity: false` | replaces the default opener |
| `skill-filesystem` | `customSkillDirs` | adds one more skill root |

Skill roots, in priority order: `<project>/.dsh/skills` → `<project>/.agents/skills` → `customSkillDirs` → `~/.dsh/skills` → `~/.agents/skills`.

Read [`docs/how-it-works.md`](docs/how-it-works.md) for the full mechanics (written from the shipped source).

## Cost

| approach | fixed cost per request | when using a skill |
|---|---|---|
| mount everything | ~54.7K chars | instant |
| curated 30 + index | ~10K chars | one extra index read |

## Uninstall

```powershell
dsh plugin --profile desktop remove dsh-eva
.\scripts\install.ps1 -Uninstall
```

Remove `dsh-eva` from `dsh.profile.bundles` in the profile's `package.json` and restart.

## License

MIT