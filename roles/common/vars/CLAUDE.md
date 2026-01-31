# Claude Permissions Configuration

This directory contains `claude_permissions.yml` which defines the permission rules merged into `~/.claude/settings.json` during provisioning.

## Permission Syntax

Use the modern syntax with space-asterisk for wildcards:
- `Bash(command *)` - matches `command` followed by any arguments
- `Bash(command)` - exact match only
- `WebFetch(domain:example.com)` - domain-scoped web access
- `Read(//path/**)` - glob patterns for file reads

## Security Principles

### No Escape Hatches

**DO NOT** add permissions that allow Claude to execute arbitrary code. This includes:

- **Language interpreters**: `python`, `python3`, `ruby`, `node`, `perl`, `php`
- **Shell interpreters**: `bash`, `sh`, `zsh` (generic execution)
- **Script sourcing**: `source` (can execute arbitrary scripts)
- **Eval/exec commands**: `eval`, `exec`
- **Arbitrary execution**: `xargs` (can pipe to any command)
- **Package managers with run**: `npm`, `yarn` (can run arbitrary scripts and install dependencies)
- **Remote execution**: `ssh` (can run arbitrary remote commands)
- **Container exec**: `docker exec`, `docker compose exec` (can run arbitrary commands in containers)

### Prefer Specific Over General

When adding new permissions:

1. **Be specific**: `Bash(docker ps *)` instead of `Bash(docker *)`
2. **Limit scope**: `Bash(bundle info *)` instead of `Bash(bundle *)`
3. **Use deny rules**: Block dangerous variants even when allowing the base command
4. **Specific tool invocations**: `Bash(npx eslint *)` instead of `Bash(npx *)`

### Deny Rules

Deny rules take precedence over allow rules. Use them to block dangerous operations even when the base command is allowed. See the `deny:` section in `claude_permissions.yml` for examples.

## Adding New Permissions

Before adding a new permission:

1. **Verify necessity**: Is this command actually needed for development workflows?
2. **Check for escape hatches**: Could this command be used to run arbitrary code?
3. **Use minimal scope**: Add the most specific permission that meets the need
4. **Consider deny rules**: If allowing a broad command, deny dangerous subcommands

