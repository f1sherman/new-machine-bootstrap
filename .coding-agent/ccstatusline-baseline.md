# ccstatusline Configuration Baseline

**Date**: 2025-10-20T13:22:11+0000
**ccstatusline Latest Version**: 2.0.21

## Current State (Before TUI Configuration)

### ~/.config/ccstatusline/settings.json
**Status**: FILE_DOES_NOT_EXIST

### ~/.claude/settings.json
**Status**: FILE_DOES_NOT_EXIST

## Next Steps

1. User will run `npx ccstatusline@latest` and configure via TUI with:
   - Model Name
   - Git Branch
   - Block Timer
   - Context Length
   - Context Percentage (usable)

2. After configuration, read both files to capture the generated settings

3. Create Ansible tasks to:
   - Pin version to 2.0.21 (or latest stable at time of implementation)
   - Template the ccstatusline settings.json
   - Merge statusLine setting into Claude settings.json without overwriting

## Implementation Notes

- Use `npx ccstatusline@2.0.21` to pin version (protect against supply-chain attacks)
- For Claude settings.json: Need to handle JSON merging in Ansible to avoid overwriting existing settings
- Could use Ansible's json_query or a custom approach with jq
