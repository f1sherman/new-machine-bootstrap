---
name: personal:convert-skill-from-codex
description: >
  Convert a Codex skill to Claude Code format. Rewrite the same intent in Claude Code language.
  Use when the user wants to port a Codex skill to Claude Code.
---

# Convert Codex Skill to Claude Code

You are Claude Code. Rewrite the source skill for your own use.

## Read

- Source path: `~/.codex/skills/<skill-name>/`
- Read `SKILL.md` first.
- Read extra files only when needed.
- Focus on intent, workflow, and constraints.

## Start

- If the user did not name a skill, list `~/.codex/skills/` and ask which one to convert.
- Wait for the answer.

## Rewrite

- Keep the same scope and goal.
- Express the workflow in Claude Code terms.
- Use Claude agents and `Task` for parallel or isolated work.
- Check `~/.claude/agents/` for useful agents.
- Read agent frontmatter as needed: `name`, `description`, `tools`.
- Use background execution and tool limits when helpful.
- Stay in one conversation.

## Agents

- Use agents for exploration, analysis, pattern finding, and web research when they fit.
- Prefer the smallest agent set that covers the job.

**Find agents:**
```bash
ls ~/.claude/agents/
```

## Translate

- `Codex` (the agent) -> `Claude Code`
- `Codex attribution` -> `Claude attribution`
- `Generated with Codex` -> `Generated with Claude`
- `list-codex-sessions` -> `list-claude-sessions`
- `read-codex-session` -> `read-claude-session`
- `shell_command` -> the right Claude tool name

## Tool Map

| Codex tool | Claude tool |
|------------|-------------|
| `Read` tool | `shell_command` with `cat` or `nl -ba` |
| `Bash` tool | `shell_command` |
| `Glob` tool | `shell_command` with `rg --files -g "pattern"` |
| `Grep` tool | `shell_command` with `rg` |
| `Edit` tool | `apply_patch` |
| `Write` tool | `shell_command` with heredoc or `apply_patch` |
| `Task` tool (sub-agents) | Use `Task` with Claude agents |
| `WebSearch` / `WebFetch` | Not available. Ask the user or skip. |

## Pattern Swaps

- Sub-agent spawning -> use Task agents, then synthesize.
- Task tool references -> use Task directly.
- Main agent / sub-agents -> remove the hierarchy.
- `personal:web-search-researcher` -> ask the user for the missing info.
- `WebSearch` / `WebFetch` -> ask the user or skip.

## Supporting Files

- Update templates, scripts, and examples.
- Apply the same replacements everywhere in the skill directory.

## Validate

- Write the result to `~/.claude/skills/<skill-name>/`.
- Check for stray `Codex` references.
- Check the workflow still matches the source skill.
- Check YAML frontmatter.
- Check that all referenced agents exist in `~/.claude/agents/`.
- Check all source files are accounted for.
- Summarize: converted skill, intent, key adaptations, output path.
