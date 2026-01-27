---
name: personal:convert-skill-from-claude
description: >
  Convert a Claude Code skill to Codex format. You are Codex receiving a Claude skill and rewriting it for yourself.
  Use when the user wants to port a Claude skill to Codex.
---

# Convert Claude Code Skill to Codex

You are Codex. You're receiving a Claude Code skill and need to rewrite it for yourself.

## Finding Claude Skills

Claude skills are located at `~/.claude/skills/`. Each skill is a directory containing:
- `SKILL.md` - The main skill definition
- Additional files - Templates, scripts, examples, or other supporting files

To list available Claude skills:
```bash
ls ~/.claude/skills/
```

## Initial Response

If the user has not specified which skill to convert, list the available Claude skills and ask them to choose:

```
I'll help you convert a Claude skill to Codex format.

Available Claude skills:
[list from ~/.claude/skills/]

Which skill would you like me to convert?
```

Then wait for the user's input before proceeding.

## Your Approach

Don't think about "removing Claude features." Instead:

1. Read the Claude skill to understand what it accomplishes
2. Write a fresh Codex skill that achieves the same goal using your native capabilities
3. Express the workflow in your idiom

## Process

### Step 1: Understand the Source Skill

Read the Claude skill from `~/.claude/skills/<skill-name>/`. Start with SKILL.md, then read other files only as needed:
- What is this skill trying to help the user accomplish?
- What are the key steps in the workflow?
- What constraints or guidelines matter?

Focus on the INTENT, not the Claude-specific implementation details like sub-agents or parallel tasks.

### Step 2: Write Your Version

Write a skill that accomplishes the same intent using your capabilities.

**Frontmatter:**
```yaml
---
name: personal:<skill-name>
description: >
  [What the skill does - write naturally, don't copy Claude's description]
---
```

**Workflow:**
Express the steps in your natural idiom:
- You can run independent tool calls in parallel via `multi_tool_use.parallel`
- You use `shell_command` with `rg`, `cat`, `ls`, etc.
- You are the agent - no delegation to sub-agents
- You keep all context in one conversation

**When Claude uses sub-agents for parallel work, you can:**
- Use `multi_tool_use.parallel` for independent operations (e.g., searching multiple patterns at once)
- Or do the work sequentially if operations depend on each other
- Use `rg` and `rg --files` for discovery
- Use `cat` or file reading for deep analysis

### Step 3: Text Replacements

Apply these replacements to agent/tool references only (not API names or documentation):

| Claude | Codex |
|--------|-------|
| `Claude Code` | `Codex` |
| `Claude` (the agent) | `Codex` |
| `Claude attribution` | `Codex attribution` |
| `Generated with Claude` | `Generated with Codex` |
| `list-claude-sessions` | `list-codex-sessions` |
| `read-claude-session` | `read-codex-session` |

**Tool name mappings:**

| Claude Tool | Codex Equivalent |
|-------------|------------------|
| `Read` tool | `shell_command` with `cat` or `nl -ba` |
| `Bash` tool | `shell_command` |
| `Glob` tool | `shell_command` with `rg --files -g "pattern"` |
| `Grep` tool | `shell_command` with `rg` |
| `Edit` tool | `apply_patch` |
| `Write` tool | `shell_command` with heredoc or `apply_patch` |
| `Task` tool (sub-agents) | Do the work yourself (see Step 4) |
| `WebSearch`/`WebFetch` | Not available - ask user or skip |

### Step 4: Handle Claude-Specific Patterns

When you encounter these Claude patterns, express them in your idiom:

**Sub-agent spawning:**
```markdown
# Claude says:
Spawn parallel sub-tasks:
- Use `personal:codebase-locator` to find files
- Use `personal:codebase-analyzer` to understand code
Wait for all to complete, then synthesize.

# You write:
Research the codebase:
- Use `rg --files` and `rg "pattern"` to find relevant files
- Read the files to understand the code
- Synthesize your findings
```

**Task tool references:**
```markdown
# Claude says:
Create multiple Task agents to research concurrently

# You write:
Research each aspect (use multi_tool_use.parallel for independent searches)
```

**"Main agent" / "sub-agents":**
- Remove these concepts entirely
- You are the only agent - just describe what to do

**Claude-only capabilities:**
- `WebSearch`/`WebFetch`: Note that this requires user assistance or skip
- `personal:web-search-researcher`: Ask user to provide information instead

### Step 5: Handle Supporting Files

For each additional file in the skill directory:
- Templates: Apply text replacements
- Scripts: Update any Claude-specific commands
- Examples: Update to reflect Codex patterns

### Step 6: Write and Validate

1. Write all files to `~/.codex/skills/<skill-name>/`
2. Validate:
   - [ ] No remaining "Claude Code" references (except when discussing cross-agent work)
   - [ ] No sub-agent or Task tool references
   - [ ] No Claude sub-agent references (`personal:codebase-*`, `personal:web-search-*`)
   - [ ] Skill name in frontmatter uses `personal:` prefix (this is fine)
   - [ ] Claude tool names converted to Codex equivalents
   - [ ] YAML frontmatter is valid
   - [ ] All source files accounted for

3. Summarize:
   ```
   Converted: [skill name]

   Intent: [what the skill accomplishes]

   Key adaptations:
   - [How you expressed parallel work]
   - [Sub-agent patterns you replaced]
   - [Tool mappings applied]
   - [Text replacements made]

   Output: [path]
   ```

## Example

**Claude skill says:**
```markdown
Spawn parallel sub-tasks for research:
- Use `personal:codebase-locator` to find WHERE files live
- Use `personal:codebase-analyzer` to understand HOW code works
- Use `personal:codebase-pattern-finder` to find similar patterns

Wait for all sub-agents to complete and synthesize findings.
```

**You would write:**
```markdown
Research the codebase:
- Pass 1 (Discovery): use `rg --files` and `rg "keyword"` to locate candidate files
- Pass 2 (Deep reads): read the most relevant files fully
- Pass 3 (Patterns): find similar patterns and examples
- Keep notes with file:line references as you go
```

You're not "removing sub-agents" - you're just writing how YOU would accomplish the same goal.
