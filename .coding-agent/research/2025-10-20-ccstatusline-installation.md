---
date: 2025-10-20T13:22:11+0000
git_commit: 9cbc6910910a0de2b8d04a82aada329b8db19d09
branch: main
repository: new-machine-bootstrap
topic: "Installing Claude Code Statusline (ccstatusline) with specific features"
tags: [research, claude-code, statusline, installation, npm, node]
status: complete
last_updated: 2025-10-20
last_updated_note: "Added actual configuration files from TUI setup"
---

# Research: Installing Claude Code Statusline (ccstatusline)

**Date**: 2025-10-20T13:22:11+0000
**Git Commit**: 9cbc6910910a0de2b8d04a82aada329b8db19d09
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question

Research how to install the Claude Code Statusline (ccstatusline) from https://github.com/sirmalloc/ccstatusline using the new-machine-bootstrap repository, with the following features enabled:
- Model Name
- Git Branch
- Block Timer
- Context Length
- Context Percentage (usable)

## Summary

**ccstatusline** is a highly customizable status line formatter for Claude Code CLI that displays real-time metrics like model name, git branch, token usage, session duration, and more. It can be installed via npm/npx or Bun without requiring global installation.

### Key Integration Points:

1. **Installation Method**: Use `npx ccstatusline@2.0.21` or `bunx ccstatusline@2.0.21` (no global install needed, version pinned for security)
2. **Configuration Location**: `~/.claude/settings.json` (currently doesn't exist in the bootstrap)
3. **Configuration Tool**: Interactive TUI for widget selection and customization
4. **Bootstrap Integration**: Add Ansible task to create Claude settings.json with statusLine configuration
5. **Dependencies**: Node.js (already managed via mise in the bootstrap at roles/macos/tasks/main.yml:146-175)

## Detailed Findings

### Installation Requirements

**Dependencies** (from README):
- Bun (v1.0+) OR Node.js 18+ (for npm)
- Git (for git widgets)
- Node.js is already configured in the bootstrap via mise

**Current Node.js Setup** (roles/macos/tasks/main.yml:146-175):
- Latest LTS Node.js installed via mise
- Global Node.js version set via mise
- Default npm packages configured via `~/.default-npm-packages`

### Installation Approach

**Recommended**: Use `npx ccstatusline@2.0.21` approach (no global installation)

This approach:
- Doesn't require adding to npm packages list
- Version pinned for security (2.0.21)
- Minimal disk space usage
- No version management needed

**Alternative**: Could use `bunx ccstatusline@2.0.21` if Bun is installed (faster startup)

### Configuration Method

**Step 1: Run Configuration TUI**
```bash
npx ccstatusline@2.0.21
```

The interactive TUI allows:
- Adding/removing/reordering status line widgets
- Customizing colors for each widget
- Configuring flex separator behavior
- Editing custom text widgets
- Installing/uninstalling to Claude Code settings
- Preview in real-time

**Step 2: Configure in Claude Code**

Create or modify `~/.claude/settings.json`:
```json
{
  "statusLine": "npx ccstatusline@2.0.21"
}
```

Or with Bun:
```json
{
  "statusLine": "bunx ccstatusline@2.0.21"
}
```

### Requested Features Configuration

All requested features are available as widgets in ccstatusline:

1. **Model Name** - Shows current Claude model (e.g., "Claude 3.5 Sonnet")
2. **Git Branch** - Displays current git branch name
3. **Block Timer** - Shows time elapsed in current 5-hour block (3 display modes available)
4. **Context Length** - Shows current context length in tokens
5. **Context Percentage (usable)** - Shows percentage of usable context (out of 160k, accounting for auto-compact at 80%)

**Configuration via TUI**:
- Run `npx ccstatusline@2.0.21`
- Navigate to "Edit widgets" or "Line Selector"
- Add the widgets: Model Name, Git Branch, Block Timer, Context Length, Context Percentage (usable)
- Customize colors if desired
- Press 'i' to install to Claude Code settings

**Settings Storage**:
- Widget configuration saved to `~/.config/ccstatusline/settings.json`
- Claude Code integration saved to `~/.claude/settings.json`

### Bootstrap Integration Strategy

**Current Claude Configuration** (roles/macos/tasks/main.yml:620-632):
- Creates `~/.claude` directory with mode 0700
- Creates `~/.claude/CLAUDE.md` file with user instructions
- Does NOT currently create `settings.json`

**Integration Approach**:

Add new Ansible task after the CLAUDE.md task (around line 633):

```yaml
- name: Configure Claude Code statusline
  copy:
    content: |
      {
        "statusLine": "npx ccstatusline@2.0.21"
      }
    dest: '{{ ansible_env.HOME }}/.claude/settings.json'
    mode: '0600'
    backup: yes
    force: no
```

**Note**: Using `force: no` ensures existing settings.json won't be overwritten if user has customized it.

**Post-Installation**:
User should run `npx ccstatusline@2.0.21` to configure specific widgets via TUI, which will:
1. Create `~/.config/ccstatusline/settings.json` with widget configuration
2. Update `~/.claude/settings.json` with the statusLine setting (if user chooses to install)

### Alternative: Template Approach

Could create a template with pre-configured widgets:

1. Create `roles/macos/templates/dotfiles/claude/settings.json.j2`:
```json
{
  "statusLine": "npx ccstatusline@2.0.21"
}
```

2. Create `roles/macos/templates/dotfiles/config/ccstatusline/settings.json.j2` with desired widgets pre-configured

3. Add Ansible tasks to install both templates

**Drawback**: Widget configuration is complex JSON structure, easier to use TUI than maintain templates.

## Code References

- `roles/macos/tasks/main.yml:146-175` - Node.js installation via mise
- `roles/macos/tasks/main.yml:620-632` - Claude configuration directory and CLAUDE.md creation
- `roles/macos/templates/dotfiles/` - Dotfiles installation pattern

## Architecture Documentation

### Current Bootstrap Architecture

**Package Management**:
- Homebrew for system tools (roles/macos/tasks/main.yml:73-105)
- mise for runtime version management (Node.js, Ruby)
- pipx for Python tools (roles/macos/tasks/main.yml:300-304)
- uv for Python tools (roles/macos/tasks/main.yml:312-314)

**Dotfiles Pattern** (roles/macos/tasks/main.yml:243-257):
- Templates stored in `roles/macos/templates/dotfiles/`
- Creates subdirectories with mode 0700
- Templates files with mode 0600
- No backup for dotfiles (backup: no)

**Claude Configuration Pattern** (roles/macos/tasks/main.yml:620-632):
- Creates `~/.claude` directory with mode 0700
- Creates config files with mode 0600
- Uses backup: yes for configuration files
- Uses `force: no` to avoid overwriting existing configs

### ccstatusline Architecture

**Configuration Files**:
- `~/.config/ccstatusline/settings.json` - Widget configuration
- `~/.claude/settings.json` - Claude Code integration

**Widget System**:
- Modular widget implementations in src/widgets/
- Core rendering logic in src/utils/renderer.ts
- Powerline font utilities in src/utils/powerline.ts
- Color definitions in src/utils/colors.ts

**Supported Features**:
- Real-time metrics (model, tokens, context)
- Git integration (branch, changes, worktree)
- Session tracking (clock, cost, block timer)
- Custom widgets (text, commands)
- Powerline styling
- Multi-line support
- TUI configuration

## Implementation Recommendations

### Minimal Integration (Recommended)

Add to `roles/macos/tasks/main.yml` after line 632:

```yaml
- name: Configure Claude Code statusline
  copy:
    content: |
      {
        "statusLine": "npx ccstatusline@2.0.21"
      }
    dest: '{{ ansible_env.HOME }}/.claude/settings.json'
    mode: '0600'
    backup: yes
    force: no
```

**Post-Bootstrap Steps**:
1. Run `npx ccstatusline@2.0.21` to configure widgets
2. Select desired widgets: Model Name, Git Branch, Block Timer, Context Length, Context Percentage (usable)
3. Customize colors as desired
4. Press 'i' to install (updates ~/.claude/settings.json)

### Complete Integration (Optional)

If you want to pre-configure widgets:

1. Run `npx ccstatusline@2.0.21` manually to configure desired widgets
2. Copy `~/.config/ccstatusline/settings.json` content
3. Create template `roles/macos/templates/dotfiles/config/ccstatusline/settings.json`
4. Add Ansible tasks to:
   - Create `~/.config/ccstatusline` directory
   - Install ccstatusline settings template
   - Install Claude settings.json template

**Drawback**: Widget configuration is complex and version-specific, manual TUI configuration is more maintainable.

## Licensing Compliance

### Meslo LG Powerline Fonts
**License**: Apache License 2.0
**Copyright**: 2009, 2010, 2013 André Berg
**Source**: https://github.com/powerline/fonts

**Requirements if storing fonts in repository**:
1. Include full Apache 2.0 LICENSE.txt file in the fonts directory
2. Include copyright notice
3. Include NOTICE file if one exists

**Apache 2.0 License Summary**:
- ✅ Commercial use allowed
- ✅ Modification allowed
- ✅ Distribution allowed
- ✅ Patent use granted
- ✅ Private use allowed
- ⚠️ Must include license and copyright notice
- ⚠️ Must state changes if modified
- ⚠️ Must include NOTICE file if present

**Recommendation**: Use Option B (download during bootstrap) to avoid license compliance overhead in your public repository. The upstream repository handles all licensing requirements.

### ccstatusline
**License**: MIT
**Copyright**: 2025 Matthew Breedlove
**Source**: https://github.com/sirmalloc/ccstatusline
**npm**: https://www.npmjs.com/package/ccstatusline

## Related Resources

- Repository: https://github.com/sirmalloc/ccstatusline
- npm package: https://www.npmjs.com/package/ccstatusline
- Powerline fonts: https://github.com/powerline/fonts
- Related tools:
  - tweakcc: https://github.com/Piebald-AI/tweakcc (Claude Code customization)
  - ccusage: https://github.com/ryoppippi/ccusage (Usage tracking, can be integrated as custom command widget)

## Actual Configuration (Post-TUI Setup)

### Generated Configuration Files

After running the TUI and configuring the requested widgets, the following files were generated:

#### ~/.config/ccstatusline/settings.json

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
        "id": "3",
        "type": "context-percentage-usable",
        "color": "brightBlack"
      },
      {
        "id": "5",
        "type": "context-length",
        "color": "magenta"
      },
      {
        "id": "7",
        "type": "session-clock",
        "color": "yellow"
      },
      {
        "id": "715cc788-fa02-4456-beaa-5ef908cf229b",
        "type": "git-branch",
        "backgroundColor": "bgBlue"
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
- **Version**: 3 (ccstatusline settings format version)
- **Widgets Configured**:
  1. Model (cyan color)
  2. Context Percentage Usable (brightBlack color)
  3. Context Length (magenta color)
  4. Session Clock (yellow color) - Note: Not originally requested but included
  5. Git Branch (blue background)
- **Powerline Enabled**: Yes, using "nord-aurora" theme
- **Flex Mode**: "full-minus-40" (reserves 40 chars for auto-compact message)
- **Note**: Block Timer was requested but not present in this configuration

#### ~/.claude/settings.json

```json
{
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@2.0.21",
    "padding": 0
  }
}
```

**Key Integration Details**:
- Uses `npx -y` flag to skip confirmation prompts
- Command type with explicit padding: 0
- Version pinned to 2.0.21 for security

### Powerline Fonts Installation

During TUI setup, ccstatusline automatically installed Powerline fonts to `~/Library/Fonts/` (required for the Powerline separators to display correctly).

**Fonts Installed** (114 font files total):
- Anonymice Powerline (4 variants)
- Arimo for Powerline (4 variants)
- Cousine for Powerline (4 variants)
- DejaVu Sans Mono for Powerline (4 variants)
- Droid Sans Mono for Powerline (3 variants)
- FuraMono Powerline (3 variants)
- Go Mono for Powerline (4 variants)
- Inconsolata for Powerline (4 variants)
- Literation Mono Powerline (4 variants)
- Meslo LG (L/M/S and DZ variants) for Powerline (24 variants)
- Monofur for Powerline (3 variants)
- Noto Mono for Powerline
- NovaMono for Powerline
- ProFont for Powerline (2 variants)
- Roboto Mono for Powerline (10 variants)
- Source Code Pro for Powerline (14 variants)
- Space Mono for Powerline (4 variants)
- Symbol Neu for Powerline
- Terminus for Powerline (16 pcf.gz variants)
- Tinos for Powerline (4 variants)
- Ubuntu Mono derivative Powerline (4 variants)

**Installation Timestamp**: 2025-10-20 08:29 (all fonts)

**Bootstrap Integration**: These fonts must be installed for Powerline mode to work correctly. The installation can be automated by:
1. Including the fonts in the repository (roles/macos/files/powerline-fonts/)
2. Using a task to copy them to ~/Library/Fonts/
3. OR using Homebrew to install font-* casks
4. OR downloading from the powerline/fonts repository during bootstrap

### Bootstrap Implementation Strategy (Revised)

Based on the actual configuration, here's the recommended implementation:

**Requirements**:
1. ✅ Pin version to prevent supply-chain attacks
2. ✅ No manual TUI configuration needed (use templates)
3. ✅ Don't overwrite existing Claude settings.json (merge instead)
4. ✅ Include all requested features

**Pinned Version**: 2.0.21 (latest as of 2025-10-20)

**Implementation Steps**:

1. Create ccstatusline settings template at `roles/macos/files/config/ccstatusline/settings.json`

2. Copy Powerline fonts from `~/Library/Fonts/` to `roles/macos/files/powerline-fonts/`

3. Add Ansible tasks to:
   - Install Powerline fonts to `~/Library/Fonts/`
   - Create `~/.config/ccstatusline` directory
   - Install ccstatusline settings (only if doesn't exist)
   - Merge statusLine setting into Claude settings.json using jq or Python

**Ansible Task Structure** (Option B - FINAL):

```yaml
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

- name: Create ccstatusline config directory
  file:
    path: '{{ ansible_env.HOME }}/.config/ccstatusline'
    state: directory
    mode: '0700'

- name: Install ccstatusline widget configuration
  copy:
    src: 'config/ccstatusline/settings.json'
    dest: '{{ ansible_env.HOME }}/.config/ccstatusline/settings.json'
    mode: '0600'
    backup: yes
    force: no

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
    merged_settings: "{{ claude_settings | combine({'statusLine': {'type': 'command', 'command': 'npx -y ccstatusline@2.0.21', 'padding': 0}}, recursive=True) }}"

- name: Write merged Claude settings.json
  copy:
    content: "{{ merged_settings | to_nice_json }}"
    dest: '{{ ansible_env.HOME }}/.claude/settings.json'
    mode: '0600'
    backup: yes
```

**Advantages of this approach**:
- No additional dependencies (jq not needed)
- Uses native Ansible filters (combine, from_json, to_nice_json)
- Properly merges with existing settings without overwriting
- Creates backup before modifying

## Open Questions (Resolved)

1. ~~Should Bun be added to Homebrew packages for faster ccstatusline startup?~~
   - **Resolution**: Stick with npx/Node.js (already installed via mise)

2. ~~Should widget configuration be templated or left to manual configuration?~~
   - **Resolution**: Template configuration for fully automated bootstrap

3. ~~Should ccstatusline settings be backed up like other dotfiles?~~
   - **Resolution**: Use backup: yes and force: no to preserve user customizations

4. ~~Should this be added to the default bootstrap or as an optional step?~~
   - **Resolution**: Add to default bootstrap as it's part of developer workflow

## Final Implementation Decisions

1. ~~Should we add Block Timer to the configuration?~~
   - **Resolution**: YES - Added to configuration template
   - Widget order: Model → Git Branch → Block Timer → Context Length → Context Percentage (usable)

2. ~~Which approach to use for JSON merging in Ansible?~~
   - **Resolution**: Use Ansible's native combine filter with from_json/to_nice_json (no dependencies)

3. ~~Should session-clock widget be removed?~~
   - **Resolution**: YES - Removed from configuration (not originally requested)

4. ~~Powerline fonts storage strategy?~~
   - **Resolution**: Option B - Download during bootstrap (FINAL DECISION)
   - Meslo LG is the most popular and widely compatible Powerline font
   - **Rationale**:
     - Avoids storing ~11MB of font binaries in public git repository
     - No license compliance overhead (upstream handles Apache 2.0 licensing)
     - Cleaner git history without binary files
   - **Implementation**: Clone https://github.com/powerline/fonts during provisioning, copy Meslo fonts, remove temp directory

## Implementation Summary

**Files to Create**:
- `roles/macos/files/config/ccstatusline/settings.json` - Widget configuration with all requested features

**Powerline Fonts Implementation**:

**DECISION: Option B - Download During Bootstrap**
- Clone https://github.com/powerline/fonts.git during provisioning
- Copy only Meslo LG fonts to ~/Library/Fonts/
- Remove temp directory after installation
- Rationale: Avoids binaries in git, no license overhead, cleaner repo

**Ansible Tasks to Add** (after line 632 in roles/macos/tasks/main.yml):
1. Download and install Powerline fonts (Option B)
2. Create ~/.config/ccstatusline directory
3. Install ccstatusline widget configuration
4. Check/read existing Claude settings.json
5. Merge statusLine setting without overwriting
6. Write merged settings with backup

**Version Pinning** (Supply-Chain Attack Prevention):
- ccstatusline: **2.0.21** (pinned via `npx -y ccstatusline@2.0.21`)
- Protects against malicious updates to the ccstatusline package

**Widget Configuration** (Final):
1. Model Name (cyan) - Shows Claude model
2. Git Branch (blue background) - Shows current git branch
3. Block Timer (yellow) - Shows time in current 5-hour block
4. Context Length (magenta) - Shows context tokens used
5. Context Percentage Usable (bright black) - Shows % of 160k usable context

**Features**:
- Powerline styling enabled with nord-aurora theme
- Full-minus-40 flex mode (prevents wrapping with auto-compact message)
- No manual TUI configuration required
- Safe merging with existing Claude settings
- Backups created before modifications
