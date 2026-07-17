---
name: z-convert-skill-from-codex
description: >
  Convert a Codex skill to Pi format. Use when the user wants to port a Codex
  skill into Pi's global skill directory.
---

# Convert Codex Skill to Pi

You are Pi. You're receiving a Codex skill and need to rewrite it for Pi.

## Finding Codex Skills

Codex skills are located at `~/.codex/skills/`. Each skill is a directory containing:
- `SKILL.md` - The main skill definition
- Additional files - Templates, scripts, examples, or other supporting files

To list available Codex skills:

```bash
ls ~/.codex/skills/
```

## Initial Response

If the user has not specified which skill to convert, list available Codex skills and ask them to choose.

## Process

### Step 1: Understand the Source Skill

Read `~/.codex/skills/<skill-name>/SKILL.md` and any supporting files needed to understand intent, workflow, constraints, scripts, and helper paths.

Focus on the intent, not Codex-specific implementation details.

### Step 2: Discover Pi Capabilities

Check available Pi skills and any project guidance:

```bash
find ~/.pi/agent/skills ~/.pi/agent/git ~/.pi/agent/npm -name SKILL.md 2>/dev/null
```

Pi skills use YAML frontmatter with a `name` and `description`. Skill names must be Pi-valid: no leading underscore and no `personal:` prefix.

### Step 3: Write the Pi Version

Create a fresh Pi skill that accomplishes the same goal using Pi's native tools and conventions.

Frontmatter:

```yaml
---
name: <skill-name-without-leading-underscore>
description: >
  <natural description of when to use this skill>
---
```

Workflow guidance:
- Use Pi tool names and paths.
- Prefer `~/.pi/agent/skills/<skill-name>/` for installed output.
- If the skill calls helper scripts, update paths and script names for Pi.
- Do not keep Codex-only commands unless the skill intentionally interacts with Codex.
- Keep cross-agent references only where they are part of the skill's purpose.

### Step 4: Handle Supporting Files

For each additional file in the Codex skill directory:
- Copy files that remain useful.
- Update paths from `~/.codex/skills` to `~/.pi/agent/skills` when they refer to the converted skill.
- Update helper names and wording for Pi.
- Preserve executable modes for scripts.

### Step 5: Validate

Before finishing:
- Ensure frontmatter YAML is valid.
- Ensure the frontmatter `name` matches the destination directory name.
- Ensure there is no leading underscore in the Pi skill name.
- Ensure all required supporting files were copied or intentionally omitted.
- Ensure remaining `Codex` references are intentional cross-agent references.

Summarize the converted skill, key adaptations, and output path.
