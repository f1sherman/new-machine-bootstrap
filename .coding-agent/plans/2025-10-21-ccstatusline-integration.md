# ccstatusline Integration Implementation Plan

## Overview

Integrate ccstatusline (Claude Code statusline formatter) into the new-machine-bootstrap repository to provide real-time metrics display including model name, git branch, block timer, context length, and context percentage. This implementation will be fully automated via Ansible templates and tasks, requiring no manual TUI configuration post-bootstrap.

## Current State Analysis

### What Exists Now:
- Node.js LTS installed and managed via mise (roles/macos/tasks/main.yml:146-175)
- Claude configuration directory created at ~/.claude (roles/macos/tasks/main.yml:620-624)
- Claude CLAUDE.md file created (roles/macos/tasks/main.yml:626-632)
- **No** ~/.claude/settings.json file currently created
- **No** ccstatusline configuration exists

### What's Missing:
- Powerline fonts installation (required for ccstatusline's Powerline mode)
- ccstatusline widget configuration file
- Claude Code settings.json with statusLine integration
- Safe merging logic to prevent overwriting existing Claude settings

### Key Constraints Discovered:
- Research document shows actual configuration from TUI setup (lines 300-387)
- Must use version pinning (2.0.21) for supply-chain attack prevention
- Must merge with existing settings.json if present (not overwrite)
- Must install Powerline fonts for proper display
- Meslo LG fonts are most compatible Powerline fonts

## Desired End State

### Specification:
After running `bin/provision`, the system should have:

1. **Powerline Fonts Installed**:
   - Meslo LG Slashed and Dotted fonts in ~/Library/Fonts/
   - No temporary files left behind

2. **ccstatusline Configuration**:
   - ~/.config/ccstatusline/settings.json with widgets:
     - Model Name (cyan)
     - Git Branch (blue background)
     - Block Timer (yellow)
     - Context Length (magenta)
     - Context Percentage Usable (bright black)
   - Powerline styling enabled with nord-aurora theme
   - Full-minus-40 flex mode

3. **Claude Code Integration**:
   - ~/.claude/settings.json exists with statusLine command
   - Command: `npx -y ccstatusline@2.0.21` (version pinned)
   - Existing settings preserved if file already exists

### Verification:
1. Run `claude` in a git repository
2. Statusline should display at top with all configured widgets
3. Powerline separators should render correctly (no boxes/missing glyphs)
4. Git branch widget should show current branch
5. Model widget should show current Claude model

## What We're NOT Doing

- Not installing all 114 Powerline fonts (only Meslo LG variants)
- Not using global npm installation (using npx instead)
- Not using Homebrew font casks (downloading from source)
- Not supporting manual TUI configuration (fully templated)
- Not including session-clock widget (not requested)
- Not preserving user-customized ccstatusline config (bootstrap maintains known-good config)

## Implementation Approach

Use Ansible's native capabilities to:
1. Set ccstatusline version as a variable for easy upgrades
2. Download Powerline fonts from official repository during bootstrap
3. Template ccstatusline configuration from research-validated settings
4. Use Ansible's `combine` filter to safely merge statusLine into existing Claude settings
5. Follow existing bootstrap patterns for directory creation, file permissions, and ownership

This approach avoids:
- Storing binary font files in git repository
- License compliance overhead
- External dependencies (jq, Python scripts)
- Manual post-bootstrap configuration steps

## Phase 1: Powerline Fonts Installation

### Overview
Download and install Meslo LG Powerline fonts from the official powerline/fonts repository. This ensures ccstatusline's Powerline separators render correctly without storing binary files in our repository.

### Changes Required:

#### 1. Ansible Tasks - Font Installation
**File**: `roles/macos/tasks/main.yml`
**Location**: After line 632 (after Claude CLAUDE.md task)

```yaml
- name: Set ccstatusline version
  set_fact:
    ccstatusline_version: "2.0.21"

- name: Clone powerline fonts repository
  git:
    repo: 'https://github.com/powerline/fonts.git'
    dest: '/tmp/powerline-fonts'
    depth: 1

- name: Install Meslo LG Powerline fonts
  shell: |
    cp /tmp/powerline-fonts/Meslo\ Slashed/*.ttf {{ ansible_env.HOME }}/Library/Fonts/ && \
    cp /tmp/powerline-fonts/Meslo\ Dotted/*.ttf {{ ansible_env.HOME }}/Library/Fonts/
  args:
    creates: '{{ ansible_env.HOME }}/Library/Fonts/Meslo LG M Regular for Powerline.ttf'

- name: Remove temporary fonts directory
  file:
    path: '/tmp/powerline-fonts'
    state: absent
```

**Rationale**:
- Version set as variable (`ccstatusline_version`) for easy upgrades across all tasks
- `depth: 1` minimizes clone size (only latest commit)
- `creates` parameter makes task idempotent
- Only copies Meslo LG variants (most compatible, widely used)
- Cleans up temporary directory to avoid cruft

### Success Criteria:

#### Automated Verification:
- [x] Fonts exist after bootstrap: `ls ~/Library/Fonts/Meslo*.ttf | wc -l` returns > 0
- [x] Temporary directory cleaned up: `[ ! -d /tmp/powerline-fonts ]`
- [x] Task is idempotent: Running twice doesn't re-download

#### Manual Verification:
- [ ] Open Font Book.app and verify Meslo LG Powerline fonts are installed
- [ ] Characters  and  render correctly in terminal

---

## Phase 2: ccstatusline Widget Configuration

### Overview
Create the ccstatusline widget configuration file with all requested features pre-configured, based on the validated configuration from the research document.

### Changes Required:

#### 1. Configuration File Template
**File**: `roles/macos/files/config/ccstatusline/settings.json`
**Changes**: Create new file

```json
{
  "version": 3,
  "lines": [
    [
      {
        "id": "1",
        "type": "model",
        "color": "cyan"
      },
      {
        "id": "2",
        "type": "git-branch",
        "backgroundColor": "bgBlue"
      },
      {
        "id": "3",
        "type": "block-timer",
        "color": "yellow"
      },
      {
        "id": "4",
        "type": "context-length",
        "color": "magenta"
      },
      {
        "id": "5",
        "type": "context-percentage-usable",
        "color": "brightBlack"
      }
    ],
    [],
    []
  ],
  "flexMode": "full-minus-40",
  "compactThreshold": 60,
  "colorLevel": 2,
  "defaultPadding": " ",
  "inheritSeparatorColors": false,
  "globalBold": false,
  "powerline": {
    "enabled": true,
    "separators": [
      ""
    ],
    "separatorInvertBackground": [
      false
    ],
    "startCaps": [],
    "endCaps": [],
    "theme": "nord-aurora",
    "autoAlign": false
  }
}
```

**Key Configuration Details**:
- All 5 requested widgets included (model, git-branch, block-timer, context-length, context-percentage-usable)
- Widget order optimized for readability
- Powerline enabled with nord-aurora theme
- `flexMode: "full-minus-40"` reserves space for auto-compact messages
- Version 3 format (current ccstatusline settings format)

#### 2. Ansible Tasks - Configuration Installation
**File**: `roles/macos/tasks/main.yml`
**Location**: After Powerline fonts installation tasks

```yaml
- name: Create ccstatusline config directory
  file:
    path: '{{ ansible_env.HOME }}/.config/ccstatusline'
    state: directory
    mode: '0700'
    owner: '{{ ansible_env.USER | default(ansible_user_id) }}'

- name: Install ccstatusline widget configuration
  copy:
    src: 'config/ccstatusline/settings.json'
    dest: '{{ ansible_env.HOME }}/.config/ccstatusline/settings.json'
    mode: '0600'
    owner: '{{ ansible_env.USER | default(ansible_user_id) }}'
```

**Rationale**:
- `mode: '0700'` for directory follows security best practices
- `mode: '0600'` for config file (user read/write only)
- `owner` explicitly set to current user (matches pattern from roles/macos/tasks/main.yml:44)
- Always overwrites to ensure bootstrap maintains known-good configuration
- Users can customize via TUI, but re-provisioning resets to standard config

### Success Criteria:

#### Automated Verification:
- [x] Directory created: `[ -d ~/.config/ccstatusline ]`
- [x] Config file exists: `[ -f ~/.config/ccstatusline/settings.json ]`
- [x] Config file has correct permissions: `stat -f %A ~/.config/ccstatusline/settings.json | grep 600`
- [x] Config is valid JSON: `python3 -m json.tool ~/.config/ccstatusline/settings.json > /dev/null`

#### Manual Verification:
- [ ] Config contains all 5 requested widgets when inspected
- [ ] Powerline theme is set to "nord-aurora"
- [ ] Re-running bootstrap resets config to standard (ensures consistency)

---

## Phase 3: Claude Code Integration

### Overview
Create or merge the statusLine configuration into ~/.claude/settings.json using Ansible's native JSON handling capabilities, ensuring existing settings are preserved.

### Changes Required:

#### 1. Ansible Tasks - Safe Settings Merge
**File**: `roles/macos/tasks/main.yml`
**Location**: After ccstatusline configuration installation tasks

```yaml
- name: Check if Claude settings.json exists
  stat:
    path: '{{ ansible_env.HOME }}/.claude/settings.json'
  register: claude_settings_stat

- name: Read existing Claude settings.json if it exists
  slurp:
    src: '{{ ansible_env.HOME }}/.claude/settings.json'
  register: claude_settings_content
  when: claude_settings_stat.stat.exists

- name: Parse existing Claude settings or use empty object
  set_fact:
    claude_settings: "{{ (claude_settings_content.content | b64decode | from_json) if claude_settings_stat.stat.exists else {} }}"

- name: Merge ccstatusline into Claude settings
  set_fact:
    merged_settings: "{{ claude_settings | combine({'statusLine': {'type': 'command', 'command': 'npx -y ccstatusline@' ~ ccstatusline_version, 'padding': 0}}, recursive=True) }}"

- name: Write merged Claude settings.json
  copy:
    content: "{{ merged_settings | to_nice_json }}"
    dest: '{{ ansible_env.HOME }}/.claude/settings.json'
    mode: '0600'
    owner: '{{ ansible_env.USER | default(ansible_user_id) }}'
    backup: yes
```

**Rationale**:
- Uses Ansible's `slurp` to read existing file
- Uses `from_json` and `to_nice_json` filters (no external dependencies)
- `combine` filter merges dictionaries recursively
- `backup: yes` creates backup before modification
- `owner` explicitly set to current user (matches pattern from roles/macos/tasks/main.yml:44)
- `npx -y` flag skips confirmation prompts
- Version uses `ccstatusline_version` variable for easy upgrades

**Merge Behavior**:
- If settings.json doesn't exist → creates new file with statusLine only
- If settings.json exists → adds/updates statusLine, preserves other settings
- If statusLine already exists → overwrites with our configuration

### Success Criteria:

#### Automated Verification:
- [x] Settings file exists: `[ -f ~/.claude/settings.json ]`
- [x] Settings file has correct permissions: `stat -f %A ~/.claude/settings.json | grep 600`
- [x] Settings contains statusLine: `grep -q 'statusLine' ~/.claude/settings.json`
- [x] Version is present: `grep -q 'ccstatusline@' ~/.claude/settings.json`
- [x] Settings is valid JSON: `python3 -m json.tool ~/.claude/settings.json > /dev/null`

#### Manual Verification:
- [ ] If user had existing settings (e.g., custom hooks), they are preserved after bootstrap
- [ ] Running `claude` displays the statusline with all widgets
- [ ] Backup file created if settings.json existed before

---

## Phase 4: Integration Testing

### Overview
Verify the complete integration works end-to-end with all components functioning correctly.

### Changes Required:

No code changes required - this phase is purely verification.

### Success Criteria:

#### Automated Verification:
- [x] Full bootstrap runs successfully: `bin/provision`
- [x] No Ansible task failures in ccstatusline-related tasks
- [x] All files created with correct permissions
- [x] Re-running bootstrap is idempotent (no changes on second run)

#### Manual Verification:
- [ ] Open terminal and run `claude` in a git repository
- [ ] Statusline appears at top of screen
- [ ] Model name widget displays current Claude model
- [ ] Git branch widget shows correct branch name
- [ ] Block timer shows time in current 5-hour block
- [ ] Context length shows token usage
- [ ] Context percentage shows usable percentage
- [ ] Powerline separators render correctly (no missing glyphs)
- [ ] Statusline wraps correctly on narrow terminals (flex mode working)
- [ ] All widget colors match configuration

---

## Testing Strategy

### Unit Tests:
Not applicable - this is infrastructure configuration, tested via Ansible task execution and manual verification.

### Integration Tests:
1. **Fresh Bootstrap Test**:
   - Run on fresh macOS machine
   - Verify all components install correctly
   - Verify ccstatusline displays in Claude Code

2. **Idempotency Test**:
   - Run `bin/provision` twice
   - Second run should show "ok" (not "changed") for ccstatusline tasks
   - No errors or warnings

3. **Existing Settings Test**:
   - Create ~/.claude/settings.json with custom content: `{"customKey": "customValue"}`
   - Run `bin/provision`
   - Verify customKey is preserved and statusLine is added

4. **Font Rendering Test**:
   - After bootstrap, run `claude`
   - Verify Powerline separator glyphs render correctly
   - Test in multiple terminals (Terminal.app, iTerm2, ghostty)

### Manual Testing Steps:
1. **Initial Installation**:
   ```bash
   # Run bootstrap
   bin/provision

   # Verify fonts installed
   ls ~/Library/Fonts/Meslo*.ttf

   # Verify ccstatusline config
   cat ~/.config/ccstatusline/settings.json

   # Verify Claude settings
   cat ~/.claude/settings.json
   ```

2. **Functional Testing**:
   ```bash
   # Navigate to a git repository
   cd ~/projects/some-git-repo

   # Start Claude Code
   claude

   # Verify statusline displays
   # Verify all widgets show correct information
   # Switch git branches and verify git-branch widget updates
   # Use Claude for a bit and verify context widgets update
   ```

3. **Edge Case Testing**:
   - Test in non-git directory (git-branch widget should handle gracefully)
   - Test with long branch names (verify flex mode handles wrapping)
   - Test with existing Claude settings.json (verify merge works)

## Performance Considerations

### Startup Performance:
- `npx ccstatusline@2.0.21` may have slight startup delay on first run (package download)
- Subsequent runs use cached package (faster)
- Alternative: Could use `bunx` if Bun is installed, but adds dependency

### Font Installation:
- One-time git clone of ~11MB during bootstrap
- Only copies Meslo LG fonts (~1-2MB) to ~/Library/Fonts
- Temporary directory cleaned up immediately

### Statusline Rendering:
- ccstatusline is written in TypeScript, runs efficiently
- Minimal performance impact on Claude Code
- Widget updates are fast (git operations, file reads)

## Migration Notes

### For Existing Users:
Users who already have ccstatusline manually configured:

1. **Widget Configuration**:
   - Bootstrap WILL overwrite ~/.config/ccstatusline/settings.json with standard config
   - Users can customize via TUI after bootstrap if desired
   - Re-running bootstrap resets to known-good configuration

2. **Claude Settings**:
   - Bootstrap merges statusLine into existing settings
   - Other settings (hooks, custom commands) are preserved
   - Backup created before modification

3. **Fonts**:
   - If Powerline fonts already installed, task is idempotent (`creates` parameter)
   - No duplicate font installations

### For Fresh Installations:
- All components installed automatically
- No manual configuration required
- Ready to use immediately after bootstrap

### Rollback:
If user wants to remove ccstatusline:
1. Remove statusLine from ~/.claude/settings.json
2. (Optional) Remove ~/.config/ccstatusline/
3. (Optional) Remove Powerline fonts from ~/Library/Fonts/

## References

- Research document: `.coding-agent/research/2025-10-20-ccstatusline-installation.md`
- ccstatusline repository: https://github.com/sirmalloc/ccstatusline
- ccstatusline npm package: https://www.npmjs.com/package/ccstatusline
- Powerline fonts repository: https://github.com/powerline/fonts
- Current Node.js setup: `roles/macos/tasks/main.yml:146-175`
- Current Claude config: `roles/macos/tasks/main.yml:620-632`
- Bootstrap patterns: `roles/macos/tasks/main.yml:243-257` (dotfiles pattern)
