---
name: personal:convert-skill-from-codex
description: >
  Convert a Codex skill to Claude Code format. You are Claude Code receiving a Codex skill and rewriting it for yourself.
  Use when the user wants to port a Codex skill to Claude Code.
---

# Convert Codex Skill to Claude Code

You are Claude Code. You're receiving a Codex skill and need to rewrite it for yourself.

## Finding Codex Skills

Codex skills are located at `~/.codex/skills/`. Each skill is a directory containing:
- `SKILL.md` - The main skill definition
- Additional files - Templates, scripts, examples, or other supporting files

To list available Codex skills:
```bash
ls ~/.codex/skills/
```

## Initial Response

If the user has not specified which skill to convert, list the available Codex skills and ask them to choose:

```
I'll help you convert a Codex skill to Claude Code format.

Available Codex skills:
[list from ~/.codex/skills/]

Which skill would you like me to convert?
```

Then wait for the user's input before proceeding.

## Your Approach

Don't think about "adding Claude features to a Codex skill." Instead:

1. Read the Codex skill to understand what it accomplishes
2. Discover your available capabilities (sub-agents, tools)
3. Write a fresh Claude Code skill that achieves the same goal using your native capabilities
4. Express the workflow in your idiom

## Process

### Step 1: Understand the Source Skill

Read the Codex skill from `~/.codex/skills/<skill-name>/`. Start with SKILL.md:
- What is this skill trying to help the user accomplish?
- What are the key steps in the workflow?
- What constraints or guidelines matter?

Focus on the INTENT, not the Codex-specific implementation details.

### Step 2: Discover Your Capabilities

**Discover available sub-agents:**
Check `~/.claude/agents/` for available agents you can use:
```bash
ls ~/.claude/agents/
```

Each agent file (`.md`) has YAML frontmatter describing:
- `name`: The agent identifier (use this with the Task tool)
- `description`: What the agent specializes in
- `tools`: What tools the agent has access to

Read the agent files to understand what specialized agents are available to you. Common patterns include agents for:
- Codebase exploration and file discovery
- Code analysis and understanding
- Pattern finding and examples
- Web research (if available)

**Your core capabilities:**
- **Task tool**: Spawn sub-tasks that run in parallel with their own context
- **Background execution**: Run long tasks in background while continuing work
- **Tool restrictions**: Give sub-tasks limited tool access (e.g., read-only)
- **Direct tools**: Grep, Glob, Read, Edit, Write, Bash, etc.

### Step 3: Write Your Version

Write a skill that accomplishes the same intent using your capabilities.

**Frontmatter:**
```yaml
---
name: personal:<skill-name>
description: >
  [What the skill does - write naturally, don't copy Codex's description]
---
```

**Workflow:**
Express the steps in your natural idiom:
- You can spawn sub-tasks via the Task tool for parallel or isolated work
- Reference any available agents you discovered in Step 2 that would help
- You can run tasks in the background
- You can restrict tools for sub-tasks (e.g., read-only analysis)

**Consider using sub-tasks when:**
- Multiple independent operations could run in parallel
- High-volume output would clutter your main context
- Operations benefit from restricted tool access
- Long-running tasks could run in background
- A specialized agent exists that's well-suited for the task

**Keep it sequential when:**
- Steps depend on each other's results
- The workflow is simple and linear
- Sub-tasks would add complexity without benefit
- No specialized agents would help

### Step 4: Text Replacements

Apply these replacements where they appear:

| Codex | Claude Code |
|-------|-------------|
| `Codex` (the agent) | `Claude Code` |
| `Codex attribution` | `Claude attribution` |
| `Generated with Codex` | `Generated with Claude` |
| `list-codex-sessions` | `list-claude-sessions` |
| `read-codex-session` | `read-claude-session` |
| `shell_command` | appropriate tool (Bash, Read, etc.) |

### Step 5: Handle Supporting Files

For each additional file in the skill directory:
- Templates: Apply text replacements
- Scripts: Update any Codex-specific commands
- Examples: Update to reflect Claude Code patterns

### Step 6: Write and Validate

1. Write all files to `~/.claude/skills/<skill-name>/`
2. Validate:
   - [ ] No remaining "Codex" references (except when discussing cross-agent work)
   - [ ] Workflow uses your native patterns naturally
   - [ ] Any referenced agents actually exist in `~/.claude/agents/`
   - [ ] YAML frontmatter is valid
   - [ ] All source files accounted for

3. Summarize:
   ```
   Converted: [skill name]

   Intent: [what the skill accomplishes]

   Key adaptations:
   - [How you expressed the workflow in your idiom]
   - [Any sub-agents you leveraged and why]
   - [Text replacements made]

   Output: [path]
   ```

## Example

**Codex skill says:**
```markdown
Research the codebase:
- Use `rg` to find files
- Read relevant files with `shell_command cat`
- Keep notes as you go
```

**If you have relevant agents**, you might write:
```markdown
Research the codebase:
- Use a codebase exploration agent (if available) to find relevant files
- Use an analysis agent (if available) to understand implementation details
- Synthesize findings from sub-tasks
```

**If sub-tasks aren't warranted** or no relevant agents exist:
```markdown
Research the codebase:
- Use Grep and Glob to find relevant files
- Read the files to understand the implementation
- Keep notes with file:line references
```

Choose based on whether parallelization actually helps the workflow and what agents are available to you.
