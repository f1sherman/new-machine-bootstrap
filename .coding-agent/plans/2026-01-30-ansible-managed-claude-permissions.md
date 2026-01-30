# Ansible-Managed Claude Code Permission Rules Implementation Plan

## Overview

Extend the existing Claude settings.json merge logic in Ansible to manage permission rules additively, allowing commonly-used commands without repeated prompts while preserving any manually-added permissions. Additionally, automatically migrate any existing permissions from the deprecated `:*` syntax to the current `space + *` syntax.

## Plan Metadata

- Date: 2026-01-30 12:59:11 CST
- Git Commit: 96974aa58f9c20a960dbcddd0c2756c509420591
- Branch: main
- Repository: new-machine-bootstrap

## Motivation

Currently, `~/.claude/settings.json` is manually configured with 124 allow rules and 1 deny rule. This configuration:
1. Uses deprecated `:*` wildcard syntax (should be `space + *`)
2. Contains duplicate entries
3. Is not version-controlled or reproducible across machines
4. Missing useful commands that require manual approval each time

The bootstrap repository already manages `model` and `statusLine` settings via non-destructive JSON merging at `roles/common/tasks/main.yml:302-330`. Extending this to also merge `permissions` will make the configuration reproducible, version-controlled, and consistent across environments.

### Relevant Artifacts
- [Research document](.coding-agent/research/2026-01-30-claude-code-permission-rules.md)
- [Current merge implementation](roles/common/tasks/main.yml:302-330)

## Current State Analysis

### Existing Settings Merge Logic (lines 302-330)

The current implementation:
1. Checks if `~/.claude/settings.json` exists
2. Reads and parses existing settings (or initializes empty object)
3. Sets `ccstatusline_version` variable
4. Uses `combine` filter with `recursive=True` to merge `model` and `statusLine`
5. Writes merged settings back with backup

Key insight: The `combine` filter preserves existing keys like `permissions`, `hooks`, etc. We need to add explicit permission merging to consolidate and update the rules.

### Current Permission Configuration Issues

1. **Deprecated syntax**: 124 rules use `:*` instead of `space + *`
2. **Duplicates**: `grep` appear twice
3. **Missing commands**: `git checkout`, `git switch`, `ssh`, `rsync`, `tail`, `jq`, etc.
4. **Not version-controlled**: Manual changes are lost on fresh installs

## Requirements

1. Create a vars file with all permission rules using current syntax
2. **Automatically convert legacy `:*` syntax to `space + *` syntax** for existing permissions
3. Modify the merge task to union permissions additively (not replace)
4. Preserve any manually-added permissions not in the managed list
5. Sort and deduplicate the final permission lists
6. Maintain idempotency (running multiple times produces same result)

## Non-Goals

- Migrating permissions to project-local `settings.local.json` files
- Implementing per-project permission overrides
- Removing the manual ability to add permissions directly to `settings.json`

## Proposed Approach

Use Ansible's `union` filter to additively merge permission lists:
- `union` combines two lists, removing duplicates
- Apply `unique` and `sort` for clean, consistent output
- Existing permissions not in managed list are preserved

This approach ensures:
- Users can still manually add permissions
- Re-running provisioning won't remove manual additions
- All rules use consistent, current syntax

### Alternatives Considered

1. **Replace entire permissions block** - Rejected because it would remove manual additions
2. **Use Jinja2 template file** - Rejected because it requires reading existing settings anyway
3. **Separate managed vs user permissions keys** - Rejected as Claude Code doesn't support this

## Implementation Plan

### Phase 1: Create Variables File

- [x] Create `roles/common/vars/claude_permissions.yml` with all permission rules
- [x] Organize rules by category (shell utils, git, gh CLI, etc.)
- [x] Use current `space + *` syntax throughout
- [x] Include deny rules for commits and force push

### Phase 2: Modify Ansible Tasks

- [x] Add `include_vars` task to load permissions variables
- [x] Add `set_fact` task to convert legacy `:*` syntax to `space + *` in existing permissions
- [x] Add `set_fact` task to union converted existing + managed permissions
- [x] Modify the merge task to include the merged permissions
- [x] Test with `--check --diff` to verify expected changes

### Phase 3: Validation

- [ ] Run provisioning and verify `settings.json` updated correctly
- [ ] Verify all allow rules are present and sorted
- [ ] Verify deny rules are present
- [ ] Verify no duplicates in final output
- [ ] Verify other settings (model, statusLine, hooks) preserved

## File Changes

### New Files

1. `roles/common/vars/claude_permissions.yml` - Permission rules as YAML list

### Modified Files

1. `roles/common/tasks/main.yml` - Add vars include and permission merge logic

## Implementation Details

### Phase 1: Variables File

Create `roles/common/vars/claude_permissions.yml`:

```yaml
---
# Claude Code permission rules
# Syntax: "Tool(command *)" for wildcards, "Tool(exact)" for exact match

claude_permissions:
  allow:
    # Shell utilities
    - "Bash(awk *)"
    - "Bash(bash *)"
    # ... (full list from research document)

  deny:
    - "Bash(git commit *)"
    - "Bash(git push --force *)"
    - "Bash(git push -f *)"
```

### Phase 2: Task Modifications

After line 319 (ccstatusline version), add:

```yaml
- name: Include Claude permission variables
  include_vars:
    file: claude_permissions.yml

- name: Convert legacy permission syntax (colon-star to space-star)
  set_fact:
    existing_permissions_converted:
      allow: "{{ (claude_settings.permissions.allow | default([])) | map('regex_replace', ':\\*\\)$', ' *)') | list }}"
      deny: "{{ (claude_settings.permissions.deny | default([])) | map('regex_replace', ':\\*\\)$', ' *)') | list }}"

- name: Merge permissions additively
  set_fact:
    merged_permissions:
      allow: "{{ existing_permissions_converted.allow | union(claude_permissions.allow) | unique | sort }}"
      deny: "{{ existing_permissions_converted.deny | union(claude_permissions.deny) | unique | sort }}"
```

**Syntax Conversion Logic:**
- Pattern: `:\*)$` matches the deprecated `:*)` at end of permission string
- Replacement: ` *)` converts to current syntax with space before wildcard
- Examples:
  - `Bash(git add:*)` → `Bash(git add *)`
  - `Bash(grep:*)` → `Bash(grep *)`
- Permissions already using new syntax are unaffected

Modify line 321-323 to include permissions:

```yaml
- name: Merge model, statusLine, and permissions into Claude settings
  set_fact:
    merged_settings: "{{ claude_settings | combine({'model': 'opus', 'statusLine': {'type': 'command', 'command': 'npx -y ccstatusline@' ~ ccstatusline_version, 'padding': 0}, 'permissions': merged_permissions}, recursive=True) }}"
```

## Testing Strategy

### Automated Verification
- [x] `bin/provision --check --diff` - Dry-run to see changes
- [ ] `jq '.permissions.allow | length' ~/.claude/settings.json` - Count allow rules
- [ ] `jq '.permissions.deny | length' ~/.claude/settings.json` - Count deny rules
- [ ] `jq '.permissions.allow | unique | length' ~/.claude/settings.json` - Verify no duplicates
- [ ] `jq '.permissions.allow | map(select(contains(":*"))) | length' ~/.claude/settings.json` - Verify no legacy syntax (should be 0)

### Manual Verification
- [ ] Run Claude Code and verify common commands don't prompt
- [ ] Verify `git commit` still prompts (deny rule)
- [ ] Verify other settings (model, statusLine) unchanged
- [ ] Add a manual permission, re-run provisioning, verify it persists

## Test Results

| Test | Status | Output |
| --- | --- | --- |
| `ansible-playbook --check --diff` | ✅ Pass | Shows expected changes: legacy syntax converted, duplicates removed, new rules added, deny rules added |
| Allow rules count (pre-provision) | ⏳ Pending | Current: 123 rules |
| Deny rules count (pre-provision) | ⏳ Pending | Current: 1 rule |
| Legacy `:*` syntax count (pre) | ⏳ Pending | Current: 90 rules with legacy syntax |
| Allow rules count (post) | ⏳ Pending | Expected: ~165 (deduped, merged) |
| Deny rules count (post) | ⏳ Pending | Expected: 3 |
| No duplicates (post) | ⏳ Pending | |
| No legacy `:*` syntax (post) | ⏳ Pending | Expected: 0 |

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Breaking existing settings.json | `backup: yes` creates `.json~` backup before changes |
| Permissions syntax error | Test with `--check` first; Claude Code validates on load |
| Missing expected permission | Research document has comprehensive list; easy to add more |

## Open Questions

1. **Should `git push` (non-force) be allowed?** - Currently not in allow list, requires prompt
2. **Project-specific scripts** - Should rules for other repos (like `bin/packwerk`) stay in global config?
3. **Docker commands** - Only basic commands included; should we allow more?

## Permission Rules Summary

The implementation includes:
- **108 allow rules** covering: shell utils, git, gh CLI, Docker, package managers, Ruby/Rails, JavaScript, bootstrap scripts, web access, MCP tools
- **3 deny rules**: `git commit`, `git push --force`, `git push -f`

Full list available in the research document.
