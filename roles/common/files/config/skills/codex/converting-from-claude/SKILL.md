---
name: personal:convert-skill-from-claude
description: >
  Convert a Claude Code skill to Codex format. Rewrite the same intent in Codex language.
  Use when the user wants to port a Claude skill to Codex.
---

# Convert Claude Code Skill to Codex

You are Codex. Rewrite the source skill for your own use.

## Read

- Source path: `~/.claude/skills/<skill-name>/`
- Read `SKILL.md` first.
- Read extra files only when needed.
- Focus on intent, workflow, and constraints.

## Start

- If the user did not name a skill, list `~/.claude/skills/` and ask which one to convert.
- Wait for the answer.

## Rewrite

- Keep the same scope and goal.
- Express the workflow in Codex terms.
- Use `multi_tool_use.parallel` for independent work.
- Use `shell_command` with `rg`, `cat`, `ls`, and friends.
- Do not delegate to sub-agents.
- Stay in one conversation.

## Capabilities

- Use parallel tool calls only when the work is independent.
- Use `rg` and `rg --files` for discovery.
- Use `cat` or `nl -ba` for file reads.
- Keep the implementation in one context.

## Translate

- `Claude Code` -> `Codex`
- `Claude` (the agent) -> `Codex`
- `Claude attribution` -> `Codex attribution`
- `Generated with Claude` -> `Generated with Codex`
- `list-claude-sessions` -> `list-codex-sessions`
- `read-claude-session` -> `read-codex-session`

## Tool Map

| Claude tool | Codex tool |
|-------------|------------|
| `Read` tool | `shell_command` with `cat` or `nl -ba` |
| `Bash` tool | `shell_command` |
| `Glob` tool | `shell_command` with `rg --files -g "pattern"` |
| `Grep` tool | `shell_command` with `rg` |
| `Edit` tool | `apply_patch` |
| `Write` tool | `shell_command` with heredoc or `apply_patch` |
| `Task` tool (sub-agents) | Do the work yourself |
| `WebSearch` / `WebFetch` | Not available. Ask the user or skip. |

## Pattern Swaps

- Sub-agent spawning -> use `multi_tool_use.parallel` for independent searches.
- Task tool references -> do the work yourself.
- Main agent / sub-agents -> remove the hierarchy.
- `personal:codebase-*` -> replace with direct file discovery and reads.
- `personal:web-search-*` -> ask the user for the missing info.
- `WebSearch` / `WebFetch` -> ask the user or skip.

## Supporting Files

- Update templates, scripts, and examples.
- Apply the same replacements everywhere in the skill directory.

## Validate

- Write the result to `~/.codex/skills/<skill-name>/`.
- Check for stray `Claude` references.
- Check the workflow still matches the source skill.
- Check YAML frontmatter.
- Check that all source files are accounted for.
- Check that any referenced agents actually exist in `~/.claude/agents/`.
- Summarize: converted skill, intent, key adaptations, output path.
