---
date: 2026-01-30T10:15:19-06:00
git_commit: 5283bca25343ca5232abc97a29da1298d8cbd99f
branch: main
repository: f1sherman/new-machine-bootstrap
topic: "Claude Code Permission Rules Configuration"
tags: [research, claude-code, permissions, settings]
status: complete
last_updated: 2026-01-30
last_updated_note: "Added implementation plan for Ansible-managed permissions with additive merge"
---

# Research: Claude Code Permission Rules Configuration

**Date**: 2026-01-30 10:15:19 CST
**Git Commit**: 5283bca25343ca5232abc97a29da1298d8cbd99f
**Branch**: main
**Repository**: f1sherman/new-machine-bootstrap

## Research Question

What permission rules should be added to `~/.claude/settings.json` to allow commonly-used commands without repeated prompts?

## Summary

Your current `~/.claude/settings.json` already has an extensive permission configuration with 124 allow rules and 1 deny rule. The configuration covers most common development workflows including git operations, Ruby/Rails commands, JavaScript/yarn commands, Docker, GitHub CLI, and various shell utilities.

**Note**: Your current config uses the deprecated `:*` wildcard syntax. The current syntax uses `space + *` (e.g., `Bash(git add *)` not `Bash(git add:*)`).

## Current Configuration Analysis

### Existing Allow Rules (124 total)

**Git Operations** (14 rules):
- `git add`, `git branch`, `git check-ignore`, `git cherry-pick`, `git fetch`, `git diff`, `git log`, `git mv`, `git restore`, `git rev-parse`, `git show`, `git stash`, `git status`, `git-changed-files`

**Ruby/Rails** (21 rules):
- `bin/bundle`, `bin/rails`, `bin/rspec`, `bin/rubocop`, `bin/restart`, `bin/setup`
- `bundle exec rspec`, `bundle info`, `bundle show`, `bundle update`
- Various project-specific scripts

**JavaScript/Node** (7 rules):
- `npx eslint`, `npx lint-staged`, `yarn format`, `yarn lint`, `yarn run eslint`, `yarn storybook`

**GitHub CLI** (11 rules):
- `gh api`, `gh pr checks/diff/list/view`, `gh run cancel/download/list/view`, `gh workflow run`, `gh workflow`

**Shell Utilities** (20+ rules):
- `awk`, `bash`, `cat`, `cd`, `curl`, `dig`, `echo`, `find`, `for`, `grep`, `head`, `ls`, `mkdir`, `mv`, `rg`, `rm`, `sed`, `test`, `timeout`, `wc`, `xargs`, `yamllint`

**Docker** (4 rules):
- `docker compose exec`, `docker rm`, `docker start`, `docker stop`

**MCP Tools** (10 rules):
- Atlassian JIRA integration
- Ember testing
- GitHub file/issue operations
- PostgreSQL queries

**WebFetch Domains** (10 rules):
- Rails docs, Anthropic docs, GitHub, OpenAI, Datadog

### Existing Deny Rules (1 rule)

- `Bash(git commit *)` - Requires explicit approval for commits (aligns with your CLAUDE.md instructions)

## Permission Rule Syntax Reference

**Current Syntax** (use this):
- `Tool` or `Tool(*)` - Match all uses
- `Tool(exact command)` - Exact match
- `Tool(prefix *)` - Prefix with any suffix (space before `*`)
- `Tool(* suffix)` - Any prefix with specific suffix

**Deprecated Syntax** (avoid):
- `Tool(prefix:*)` - Old wildcard syntax, still works but deprecated

**File Paths**:
- Relative: `Read(./path/to/file)`
- Absolute: `Read(//Users/brianjohn/path)` (double slash)
- Glob: `Read(./src/**/*.ts)`

**Domains**:
- `WebFetch(domain:example.com)`

## Recommended Additions

Based on analysis of your workflow and common development patterns, here are recommended additions:

### High-Value Additions (Frequently Used)

```json
{
  "permissions": {
    "allow": [
      "Bash(git checkout *)",
      "Bash(git switch *)",
      "Bash(git rebase *)",
      "Bash(git merge *)",
      "Bash(git pull *)",
      "Bash(git reset *)",
      "Bash(git clean *)",
      "Bash(gh codespace *)",
      "Bash(gh issue *)",
      "Bash(gh pr create *)",
      "Bash(gh pr merge *)",
      "Bash(gh repo *)",
      "Bash(ssh *)",
      "Bash(scp *)",
      "Bash(rsync *)",
      "Bash(tail *)",
      "Bash(sort *)",
      "Bash(uniq *)",
      "Bash(cut *)",
      "Bash(tr *)",
      "Bash(diff *)",
      "Bash(touch *)",
      "Bash(chmod *)",
      "Bash(cp *)",
      "Bash(date *)",
      "Bash(which *)",
      "Bash(type *)",
      "Bash(file *)",
      "Bash(pwd)",
      "Bash(env *)",
      "Bash(export *)",
      "Bash(source *)",
      "Bash(mise *)",
      "Bash(brew *)",
      "Bash(pip *)",
      "Bash(pipx *)",
      "Bash(npm *)",
      "Bash(node *)",
      "Bash(jq *)",
      "Bash(yq *)",
      "Bash(ansible *)",
      "Bash(ansible-playbook *)"
    ]
  }
}
```

### Bootstrap Repository Specific

For this repository specifically:

```json
{
  "permissions": {
    "allow": [
      "Bash(bin/codespace-create *)",
      "Bash(bin/codespace-ssh *)",
      "Bash(bin/sync-to-codespace *)",
      "Bash(bin/sync-dev-env *)",
      "Bash(csr *)"
    ]
  }
}
```

### Recommended Deny Rules

```json
{
  "permissions": {
    "deny": [
      "Bash(git push --force *)",
      "Bash(git push -f *)",
      "Bash(rm -rf / *)",
      "Bash(rm -rf ~ *)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Read(**/.credentials*)",
      "Read(**/api-keys/**)"
    ]
  }
}
```

**Note**: The web research revealed that deny rules have known issues and may not be consistently enforced. Use these as an additional layer but don't rely on them as your only security measure.

## Duplicates to Remove

Your current config has these duplicates:
- `Bash(bin/packwerk check:*)` - appears twice
- `Bash(bin/restart-rails:*)` - appears twice
- `Bash(grep:*)` - appears twice

## Patterns That Could Be Consolidated

Instead of individual rules, consider these consolidated patterns:

| Current | Consolidated |
|---------|-------------|
| Multiple `gh pr ...` rules | `Bash(gh pr *)` covers all |
| Multiple `gh run ...` rules | `Bash(gh run *)` covers all |
| Multiple `bundle exec ...` rules | `Bash(bundle exec *)` covers all |

However, specific rules provide more granular control if needed.

## Recommended Complete Configuration

Here's a recommended merged configuration using the current syntax:

```json
{
  "permissions": {
    "allow": [
      "Bash(ansible *)",
      "Bash(ansible-playbook *)",
      "Bash(awk *)",
      "Bash(bash *)",
      "Bash(bin/bundle *)",
      "Bash(bin/codespace-create *)",
      "Bash(bin/codespace-ssh *)",
      "Bash(bin/dc *)",
      "Bash(bin/packwerk check *)",
      "Bash(bin/provision --check *)",
      "Bash(bin/provision --diff *)",
      "Bash(bin/rails *)",
      "Bash(bin/restart *)",
      "Bash(bin/rspec *)",
      "Bash(bin/rubocop *)",
      "Bash(bin/setup *)",
      "Bash(bin/sync-to-codespace *)",
      "Bash(brew *)",
      "Bash(bundle exec *)",
      "Bash(bundle graph *)",
      "Bash(bundle info *)",
      "Bash(bundle show *)",
      "Bash(bundle update *)",
      "Bash(cat *)",
      "Bash(cd *)",
      "Bash(chmod *)",
      "Bash(cp *)",
      "Bash(csr *)",
      "Bash(curl *)",
      "Bash(cut *)",
      "Bash(date *)",
      "Bash(diff *)",
      "Bash(dig *)",
      "Bash(docker compose exec *)",
      "Bash(docker rm *)",
      "Bash(docker start *)",
      "Bash(docker stop *)",
      "Bash(echo *)",
      "Bash(env *)",
      "Bash(file *)",
      "Bash(find *)",
      "Bash(for *)",
      "Bash(gh api *)",
      "Bash(gh codespace *)",
      "Bash(gh issue *)",
      "Bash(gh pr *)",
      "Bash(gh repo *)",
      "Bash(gh run *)",
      "Bash(gh workflow *)",
      "Bash(git add *)",
      "Bash(git branch *)",
      "Bash(git check-ignore *)",
      "Bash(git checkout *)",
      "Bash(git cherry-pick *)",
      "Bash(git clean *)",
      "Bash(git diff *)",
      "Bash(git fetch *)",
      "Bash(git log *)",
      "Bash(git merge *)",
      "Bash(git mv *)",
      "Bash(git pull *)",
      "Bash(git rebase *)",
      "Bash(git reset *)",
      "Bash(git restore *)",
      "Bash(git rev-parse *)",
      "Bash(git show *)",
      "Bash(git stash *)",
      "Bash(git status *)",
      "Bash(git switch *)",
      "Bash(git-changed-files *)",
      "Bash(grep *)",
      "Bash(head *)",
      "Bash(jq *)",
      "Bash(ls *)",
      "Bash(mise *)",
      "Bash(mkdir *)",
      "Bash(mv *)",
      "Bash(node *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(pip *)",
      "Bash(pipx *)",
      "Bash(pwd)",
      "Bash(python3 *)",
      "Bash(rg *)",
      "Bash(rm *)",
      "Bash(rsync *)",
      "Bash(ruby *)",
      "Bash(scp *)",
      "Bash(sed *)",
      "Bash(sort *)",
      "Bash(source *)",
      "Bash(ssh *)",
      "Bash(tail *)",
      "Bash(test *)",
      "Bash(timeout *)",
      "Bash(touch *)",
      "Bash(tr *)",
      "Bash(type *)",
      "Bash(uniq *)",
      "Bash(wc *)",
      "Bash(which *)",
      "Bash(xargs *)",
      "Bash(yamllint *)",
      "Bash(yarn *)",
      "Bash(yq *)",
      "Bash(~/bin/spec-metadata)",
      "Bash(~/.claude/skills/create-pull-request/create-draft-pr *)",
      "Bash(~/.claude/skills/create-pull-request/gather-pr-context *)",
      "WebFetch(domain:api.rubyonrails.org)",
      "WebFetch(domain:docs.anthropic.com)",
      "WebFetch(domain:docs.datadoghq.com)",
      "WebFetch(domain:docs.github.com)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:guides.rubyonrails.org)",
      "WebFetch(domain:help.openai.com)",
      "WebFetch(domain:platform.openai.com)",
      "WebSearch",
      "mcp__atlassian__createJiraIssue",
      "mcp__atlassian__getAccessibleAtlassianResources",
      "mcp__atlassian__getVisibleJiraProjects",
      "mcp__atlassian__lookupJiraAccountId",
      "mcp__postgresql__query"
    ],
    "deny": [
      "Bash(git commit *)",
      "Bash(git push --force *)",
      "Bash(git push -f *)"
    ]
  }
}
```

## Key Changes from Current Config

### Syntax Migration
- All rules converted from deprecated `:*` syntax to current `space + *` syntax

### Added (41 new rules):
- **Git**: `checkout`, `switch`, `rebase`, `merge`, `pull`, `reset`, `clean`
- **GitHub CLI**: `codespace`, `issue`, `repo` (and consolidated `pr`/`run`)
- **Shell utilities**: `tail`, `sort`, `uniq`, `cut`, `tr`, `diff`, `touch`, `chmod`, `cp`, `date`, `which`, `type`, `file`, `pwd`, `env`, `source`
- **Remote**: `ssh`, `scp`, `rsync`
- **Package managers**: `mise`, `brew`, `pip`, `pipx`, `npm`, `node`
- **Data tools**: `jq`, `yq`
- **Ansible**: `ansible`, `ansible-playbook`
- **Bootstrap scripts**: `codespace-create`, `codespace-ssh`, `sync-to-codespace`, `csr`

### Consolidated:
- `yarn format/lint/run eslint/storybook` → `yarn *`
- `npx eslint/lint-staged` → `npx *`
- Multiple `gh pr/run` variants → `gh pr *`, `gh run *`
- Multiple `bundle exec` variants → `bundle exec *`

### Removed duplicates:
- `grep` (was listed twice)

### Added deny rules:
- Force push protection (aligns with CLAUDE.md safety guidelines)

## Security Considerations

1. **Deny rules are unreliable** - Research shows they may not be consistently enforced
2. **Your CLAUDE.md already instructs** against commits/PRs without explicit request
3. **API keys stored in `~/.config/api-keys/`** - not in project directories, so Read rules don't need to block them
4. **Force push deny rules** added as defense-in-depth

## Related Research

- Claude Code official settings documentation: https://code.claude.com/docs/en/settings
- GitHub issues on deny rule enforcement: #8961, #6699

## Implementation Plan: Ansible-Managed Permissions

### Overview

The bootstrap repository already manages `~/.claude/settings.json` via non-destructive JSON merging at `roles/common/tasks/main.yml:302-330`. Currently it merges `model` and `statusLine` settings. We'll extend this to also merge `permissions` using an **additive strategy** that preserves any manually-added permissions.

### File Structure

Create a new vars file to store the permission rules:

```
roles/common/vars/
└── claude_permissions.yml    # New file with permission rules
```

### Implementation Steps

#### 1. Create `roles/common/vars/claude_permissions.yml`

```yaml
---
# Claude Code permission rules
# These are merged into ~/.claude/settings.json during provisioning
# Syntax: "Tool(command *)" for wildcards, "Tool(exact)" for exact match

claude_permissions:
  allow:
    # Ansible
    - "Bash(ansible *)"
    - "Bash(ansible-playbook *)"

    # Shell utilities
    - "Bash(awk *)"
    - "Bash(bash *)"
    - "Bash(cat *)"
    - "Bash(cd *)"
    - "Bash(chmod *)"
    - "Bash(cp *)"
    - "Bash(curl *)"
    - "Bash(cut *)"
    - "Bash(date *)"
    - "Bash(diff *)"
    - "Bash(dig *)"
    - "Bash(echo *)"
    - "Bash(env *)"
    - "Bash(file *)"
    - "Bash(find *)"
    - "Bash(for *)"
    - "Bash(grep *)"
    - "Bash(head *)"
    - "Bash(jq *)"
    - "Bash(ls *)"
    - "Bash(mkdir *)"
    - "Bash(mv *)"
    - "Bash(pwd)"
    - "Bash(rg *)"
    - "Bash(rm *)"
    - "Bash(rsync *)"
    - "Bash(scp *)"
    - "Bash(sed *)"
    - "Bash(sort *)"
    - "Bash(source *)"
    - "Bash(ssh *)"
    - "Bash(tail *)"
    - "Bash(test *)"
    - "Bash(timeout *)"
    - "Bash(touch *)"
    - "Bash(tr *)"
    - "Bash(type *)"
    - "Bash(uniq *)"
    - "Bash(wc *)"
    - "Bash(which *)"
    - "Bash(xargs *)"
    - "Bash(yamllint *)"
    - "Bash(yq *)"

    # Git operations
    - "Bash(git add *)"
    - "Bash(git branch *)"
    - "Bash(git check-ignore *)"
    - "Bash(git checkout *)"
    - "Bash(git cherry-pick *)"
    - "Bash(git clean *)"
    - "Bash(git diff *)"
    - "Bash(git fetch *)"
    - "Bash(git log *)"
    - "Bash(git merge *)"
    - "Bash(git mv *)"
    - "Bash(git pull *)"
    - "Bash(git rebase *)"
    - "Bash(git reset *)"
    - "Bash(git restore *)"
    - "Bash(git rev-parse *)"
    - "Bash(git show *)"
    - "Bash(git stash *)"
    - "Bash(git status *)"
    - "Bash(git switch *)"
    - "Bash(git-changed-files *)"

    # GitHub CLI
    - "Bash(gh api *)"
    - "Bash(gh codespace *)"
    - "Bash(gh issue *)"
    - "Bash(gh pr *)"
    - "Bash(gh repo *)"
    - "Bash(gh run *)"
    - "Bash(gh workflow *)"

    # Docker
    - "Bash(docker compose exec *)"
    - "Bash(docker rm *)"
    - "Bash(docker start *)"
    - "Bash(docker stop *)"

    # Package managers
    - "Bash(brew *)"
    - "Bash(mise *)"
    - "Bash(npm *)"
    - "Bash(node *)"
    - "Bash(npx *)"
    - "Bash(pip *)"
    - "Bash(pipx *)"

    # Ruby/Rails
    - "Bash(bin/bundle *)"
    - "Bash(bin/codeownership *)"
    - "Bash(bin/dc *)"
    - "Bash(bin/packwerk check *)"
    - "Bash(bin/rails *)"
    - "Bash(bin/resetdb *)"
    - "Bash(bin/restart *)"
    - "Bash(bin/restart-rails *)"
    - "Bash(bin/rspec *)"
    - "Bash(bin/rubocop *)"
    - "Bash(bin/setup *)"
    - "Bash(bin/utils/sync-coding-rules *)"
    - "Bash(bundle exec *)"
    - "Bash(bundle graph *)"
    - "Bash(bundle info *)"
    - "Bash(bundle show *)"
    - "Bash(bundle update *)"
    - "Bash(python3 *)"
    - "Bash(ruby *)"

    # JavaScript
    - "Bash(yarn *)"

    # Bootstrap scripts
    - "Bash(bin/codespace-create *)"
    - "Bash(bin/codespace-ssh *)"
    - "Bash(bin/provision --check *)"
    - "Bash(bin/provision --diff *)"
    - "Bash(bin/sync-dev-env *)"
    - "Bash(bin/sync-to-codespace *)"
    - "Bash(csr *)"

    # Claude skills
    - "Bash(~/.claude/skills/create-pull-request/create-draft-pr *)"
    - "Bash(~/.claude/skills/create-pull-request/gather-pr-context *)"

    # File reads
    - "Read(//Users/brianjohn/projects/github-actions/pull-request-review/**)"

    # Web access
    - "WebFetch(domain:api.rubyonrails.org)"
    - "WebFetch(domain:docs.anthropic.com)"
    - "WebFetch(domain:docs.datadoghq.com)"
    - "WebFetch(domain:docs.github.com)"
    - "WebFetch(domain:github.com)"
    - "WebFetch(domain:guides.rubyonrails.org)"
    - "WebSearch"

    # MCP tools
    - "mcp__atlassian__createJiraIssue"
    - "mcp__atlassian__getAccessibleAtlassianResources"
    - "mcp__atlassian__getVisibleJiraProjects"
    - "mcp__atlassian__lookupJiraAccountId"
    - "mcp__github__get_file_contents"
    - "mcp__github__get_issue"
    - "mcp__github__list_commits"
    - "mcp__github__search_issues"
    - "mcp__postgresql__query"

  deny:
    # Require explicit approval for commits (per CLAUDE.md)
    - "Bash(git commit *)"
    # Prevent accidental force pushes
    - "Bash(git push --force *)"
    - "Bash(git push -f *)"
```

#### 2. Update `roles/common/tasks/main.yml`

Add vars inclusion near the top of the file (after any existing includes):

```yaml
- name: Include Claude permission variables
  include_vars:
    file: claude_permissions.yml
```

Add a new task to merge permissions additively (insert after line 315, before the ccstatusline version task):

```yaml
- name: Merge permissions additively
  set_fact:
    merged_permissions:
      allow: "{{ (claude_settings.permissions.allow | default([])) | union(claude_permissions.allow) | unique | sort }}"
      deny: "{{ (claude_settings.permissions.deny | default([])) | union(claude_permissions.deny) | unique | sort }}"
```

Modify the existing merge task (line 321-323) to include the merged permissions:

```yaml
# Before (current):
- name: Merge model and ccstatusline into Claude settings
  set_fact:
    merged_settings: "{{ claude_settings | combine({'model': 'opus', 'statusLine': {'type': 'command', 'command': 'npx -y ccstatusline@' ~ ccstatusline_version, 'padding': 0}}, recursive=True) }}"

# After (updated):
- name: Merge model, statusLine, and permissions into Claude settings
  set_fact:
    merged_settings: "{{ claude_settings | combine({'model': 'opus', 'statusLine': {'type': 'command', 'command': 'npx -y ccstatusline@' ~ ccstatusline_version, 'padding': 0}, 'permissions': merged_permissions}, recursive=True) }}"
```

### How It Works

1. **Additive merge**: Uses Ansible's `union` filter to combine managed permissions with any existing manual additions
2. **Non-destructive**: The `combine` filter with `recursive=True` preserves other settings like `hooks`
3. **Idempotent**: Running provisioning multiple times produces the same result
4. **Version controlled**: Permission rules live in the repository and can be tracked via git
5. **Easy to update**: Add/remove rules in `claude_permissions.yml` and re-run provisioning

### Merge Behavior

The additive merge strategy:
- Unions the allow lists (combines managed + existing, removes duplicates)
- Unions the deny lists (combines managed + existing, removes duplicates)
- Sorts alphabetically for consistent ordering
- Preserves any manual additions in `settings.json`
- Preserves other top-level keys like `hooks`

### Testing

After implementation:

```bash
# Dry-run to see what would change
bin/provision --check --diff

# Apply changes (requires sudo for other tasks)
bin/provision
```

## Open Questions

1. Should `git push` (non-force) be allowed or require approval?
2. Are there additional project-specific scripts in other repositories that should be allowed globally?
3. Should Docker commands beyond `compose exec`, `rm`, `start`, `stop` be allowed?
