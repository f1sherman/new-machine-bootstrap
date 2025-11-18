---
date: 2025-11-17 13:42:19 CST
git_commit: d8c519db56dae704e506d8f9c207edf7212a2d3e
branch: main
repository: new-machine-bootstrap
topic: "Syncing .coding-agent files between local and Codespaces"
tags: [research, codebase, sync, codespaces, dotfiles, coding-agent]
status: complete
last_updated: 2025-11-17
last_updated_note: "Added follow-up research for user requirements and technical patterns"
---

# Research: Syncing .coding-agent Files Between Local and Codespaces

**Date**: 2025-11-17 13:42:19 CST
**Git Commit**: d8c519db56dae704e506d8f9c207edf7212a2d3e
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question

How can I automatically sync my files under `.coding-agent` between my local copies of codebases and my codespaces?

## Summary

Currently, `.coding-agent` directories are **explicitly excluded** from the bootstrap repository sync to Codespaces. The existing sync mechanism (`bin/sync-to-codespace`) is **unidirectional** (local → Codespace) and **bootstrap-repo-specific** - it only syncs the bootstrap repository itself, not other codebases.

The `.coding-agent` directory in this repository contains plans and research documents (7 files total: 3 plans, 3 research docs, 1 baseline). The exclusion occurs at `bin/sync-to-codespace:106` where the tar command explicitly excludes `.coding-agent`, `.claude`, and `.git` directories.

There is **no existing mechanism** for:
- Syncing `.coding-agent` directories from arbitrary codebases
- Bidirectional synchronization (Codespace → local)
- Continuous or automatic syncing (only manual, on-demand via provisioning)

## Detailed Findings

### Current Sync Mechanism

**Location**: `bin/sync-to-codespace:106-123`

The sync uses a tar-over-SSH pipeline:

```ruby
tar_cmd = "tar czf - --no-xattrs --exclude='.git' --exclude='.coding-agent' --exclude='.claude' --exclude='*.backup' --exclude='.DS_Store' --exclude='._*' --exclude='.codespace-defaults.yml' ."
ssh_cmd = "gh codespace ssh -c #{codespace_name} -- 'mkdir -p ~/new-machine-bootstrap && cd ~/new-machine-bootstrap && tar xzf -'"
sync_cmd = "#{tar_cmd} | #{ssh_cmd}"
```

**Key Characteristics**:
- **Unidirectional**: Local → Codespace only
- **Scoped to bootstrap repo**: Only syncs `/Users/brianjohn/projects/new-machine-bootstrap` to `~/new-machine-bootstrap` in Codespace
- **Manual trigger**: Runs when user invokes `bin/sync-to-codespace` or `bin/codespace-create`
- **No reverse sync**: No mechanism to pull changes from Codespace back to local
- **Exclusions hardcoded**: The exclusion list at line 106 is not configurable

**Files Explicitly Excluded**:
1. `.git` - Git repository
2. `.coding-agent` - Coding agent files (plans, research)
3. `.claude` - Claude configuration
4. `*.backup` - Backup files
5. `.DS_Store` - macOS directory metadata
6. `._*` - macOS AppleDouble files
7. `.codespace-defaults.yml` - Codespace defaults

### .coding-agent Directory Structure

**Location**: `/Users/brianjohn/projects/new-machine-bootstrap/.coding-agent/`

```
.coding-agent/
├── ccstatusline-baseline.md
├── plans/
│   ├── 2025-10-21-ccstatusline-integration.md
│   ├── 2025-10-30-ENG-codespaces-dotfiles-setup.md
│   └── 2025-11-12-codespaces-ansible-conversion.md
└── research/
    ├── 2025-10-20-ccstatusline-installation.md
    ├── 2025-10-30-codespaces-dotfiles.md
    └── 2025-11-12-ansible-conversion-research.md
```

**File Organization**:
- **plans/**: Implementation plans with date prefixes (some with `ENG-XXXX` ticket numbers)
- **research/**: Research documents with date prefixes
- **Root level**: Baseline/reference documents
- **Naming convention**: `YYYY-MM-DD-[ENG-XXXX-]description.md`

**Purpose**:
These directories store AI-generated planning and research documents created by Claude Code slash commands like `/personal:research-codebase` and `/personal:create-plan`. The files are specific to the bootstrap repository's development history.

### Ansible File Sync Patterns

The Ansible playbooks use several patterns for file synchronization:

#### 1. Template Module with `with_filetree` (Recursive Directory Sync)

**Location**: `roles/common/tasks/main.yml:59-75`

```yaml
- name: Create dotfile subdirectories
  file:
    path: '{{ ansible_env.HOME }}/.{{ item.path }}'
    state: directory
    mode: 0700
  with_filetree: '{{ playbook_dir }}/roles/common/templates/dotfiles/'
  when: item.state == 'directory'

- name: Install shared dotfiles
  template:
    backup: no
    dest: '{{ ansible_env.HOME }}/.{{ item.path }}'
    src: '{{ item.src }}'
    mode: 0600
  with_filetree: '{{ playbook_dir }}/roles/common/templates/dotfiles/'
  when: item.state == 'file' and not item.path.startswith('._')
```

**Characteristics**:
- Two-stage: create directories first, then template files
- Uses Jinja2 templating for variable substitution
- Overwrites without backup (`backup: no`)
- Filters out macOS metadata files (`._*`)
- Deploys to `~/.claude/agents/` and `~/.claude/commands/`

#### 2. Copy Module with Backup

**Location**: `roles/common/tasks/main.yml:82-101`

Used for executable scripts:
- `~/bin/pick-files`
- `~/bin/osc52-copy`
- `~/bin/draft-pr`
- `~/bin/claude/spec-metadata`

All use `backup: yes` and mode `0755`.

#### 3. Git Module for Repository Cloning

**Location**: `roles/common/tasks/main.yml:3-15`

```yaml
- name: Clone prezto
  git:
    dest: '{{ ansible_env.HOME }}/.zprezto'
    repo: 'https://github.com/sorin-ionescu/prezto.git'
    recursive: yes
    update: yes
```

**Characteristics**:
- Idempotent: safe to run multiple times
- `update: yes` pulls latest changes
- `force: no` prevents overwriting local changes

### Dotfiles Deployment Mechanism

**Location**: `roles/common/tasks/main.yml:59-75`

Claude configuration files are deployed via **templating** (not copying or symlinking):

1. Files in `roles/common/templates/dotfiles/claude/` are processed through Jinja2
2. Written to `~/.claude/agents/` and `~/.claude/commands/`
3. Mode: `0600` (owner read/write only)
4. No backup created (`backup: no`)
5. Overwrites existing files on every provisioning run

**Flow**:
- **macOS**: User runs `bin/provision` → Ansible templates files to `~/.claude/`
- **Codespaces**: User runs `bin/sync-to-codespace` → syncs bootstrap repo (excluding `.claude/`) → runs `bin/provision` in Codespace → Ansible templates fresh files to `~/.claude/`

**Important**: The sync excludes `.claude/` from the tar archive (`bin/sync-to-codespace:106`), so local `~/.claude/` files are never copied to Codespaces. Instead, Codespaces get fresh Claude files templated from `roles/common/templates/dotfiles/claude/` during provisioning.

### Limitations for .coding-agent Sync

**Scope Limitation**:
- Current sync only handles the bootstrap repository
- Does not sync other codebases (e.g., work repositories in `/workspaces/*`)
- `.coding-agent` directories in other codebases are not touched

**Directionality Limitation**:
- Sync is strictly local → Codespace
- No mechanism to pull changes made in Codespace back to local
- Creating a plan in Codespace's workspace would not sync back to local codebase

**Automation Limitation**:
- Sync only runs when manually triggered
- No continuous sync or file watching
- No automatic sync on file changes

**Configuration Limitation**:
- Exclusion list is hardcoded
- No configuration file to customize what gets synced
- No per-codebase sync settings

## Code References

- `bin/sync-to-codespace:106` - Tar command with exclusions (including `.coding-agent`)
- `bin/sync-to-codespace:101` - User message about exclusions
- `bin/codespace-create:151-157` - Calls sync-to-codespace after Codespace creation
- `roles/common/tasks/main.yml:59-75` - Dotfiles templating with `with_filetree`
- `roles/common/tasks/main.yml:3-15` - Git module for repository cloning

## Architecture Documentation

### Current Architecture

```
Local Machine (macOS)                          GitHub Codespace
─────────────────────                          ────────────────

~/projects/new-machine-bootstrap/              ~/new-machine-bootstrap/
├── .coding-agent/ (excluded) ✗               (not present)
├── .claude/ (excluded) ✗                     (not present)
├── bin/sync-to-codespace                     ├── bin/provision
├── roles/                                    ├── roles/
└── playbook.yml ──────────[tar+ssh]─────────▶└── playbook.yml
                                                      │
                                                      │ [ansible-playbook]
                                                      ▼
                                               ~/.claude/
                                               ├── agents/
                                               └── commands/
                                               (templated from roles/common/templates/)
```

**Key Points**:
1. Bootstrap repo syncs to Codespace (excluding `.coding-agent`, `.claude`, `.git`)
2. Provisioning runs in Codespace
3. Claude files templated fresh in Codespace from roles
4. `.coding-agent` never reaches Codespace

### Patterns for File Sync

**Ansible Patterns Available**:
1. **Template + with_filetree**: Recursive directory sync with variable substitution
2. **Copy module**: Static file copying (with or without backup)
3. **Git module**: Repository cloning/updating
4. **Blockinfile**: Partial file updates (managed sections)
5. **JSON merging**: Complex JSON configuration updates

**Non-Ansible Pattern** (current):
- **tar + SSH**: Bulk file transfer with exclusions

## Related Research

- `.coding-agent/research/2025-11-12-ansible-conversion-research.md` - Ansible conversion research
- `.coding-agent/research/2025-10-30-codespaces-dotfiles.md` - Codespaces dotfiles research
- `.coding-agent/plans/2025-11-12-codespaces-ansible-conversion.md` - Ansible conversion plan

## Follow-up Research [2025-11-17 14:14:03 CST]

### User Requirements (Collected)

Based on follow-up discussion, the sync requirements are:

1. **Scope**: All codebases - sync should work for any codebase, not just bootstrap repo
   - Local and Codespace must have same git origin
   - Sync the `.coding-agent` directory between matching repositories

2. **Directionality**: Bidirectional sync required
   - Ideal: Automatic sync back to host when disconnecting from SSH
   - Fallback: Periodic or manual sync acceptable

3. **Triggering**: Automatic preferred, but flexible
   - Best: Automatic on SSH disconnect
   - Acceptable: Periodic sync while connected
   - Minimum: Manual command

4. **Destination**: Workspace directory (`/workspaces/repo/.coding-agent/`)

5. **Conflict Resolution**: Error and notify user
   - Don't auto-resolve conflicts
   - Inform user when conflicts detected
   - Let user manually resolve

### Technical Patterns Researched

#### SSH Disconnect Detection

**Server-Side (Most Reliable)**:
- **PAM (Pluggable Authentication Modules)** - Gold standard for disconnect detection
  - Edit `/etc/pam.d/sshd` to add `pam_exec.so` hook
  - Script runs on `close_session` event
  - Catches both graceful logout and abrupt disconnections
  - Requires root access to configure

- **Shell logout files** (`.bash_logout`, `.zlogout`) - Limited reliability
  - Only works for graceful exits (typing `exit`, Ctrl+D)
  - Does NOT work for: closed terminal windows, network interruptions, SIGKILL
  - Zsh: sends SIGHUP to background jobs by default
  - Bash: only sends SIGHUP when shell itself receives SIGHUP

- **Signal trapping** (`trap EXIT SIGHUP`) - Works in scripts, not interactive shells
  - EXIT traps may not execute in interactive shells (bash bug)
  - Cannot trap SIGKILL (force kill)
  - Requires `-t` flag when running via SSH: `ssh -t hostname 'script.sh'`

**Client-Side (macOS)**:
- **Shell wrapper function** - Most practical approach
  - Wrap `ssh` command with function that runs cleanup after disconnect
  - Example: `ssh() { command ssh "$@"; echo "Disconnected" }`
  - Limitation: Only works for interactive terminal, doesn't catch rsync/sftp

- **SSH LocalCommand** - Runs BEFORE session, not after
  - `LocalCommand` in `~/.ssh/config` runs after connecting but before session starts
  - No native post-disconnect hook in OpenSSH

**gh codespace ssh**:
- No built-in disconnect hooks
- Essentially wrapper around SSH
- Can use same client-side wrapper function approach

**systemd and tmux/byobu**:
- Modern systemd kills all user processes on logout by default
- Solution: Set `KillUserProcesses=no` in `/etc/systemd/logind.conf`
- Or enable user lingering: `loginctl enable-linger username`
- Critical for Codespaces with byobu auto-launch

#### Git Repository Matching

**Local Repository Detection**:
```bash
# Get remote origin URL
git config --get remote.origin.url
# Output: git@github.com:owner/repo.git or https://github.com/owner/repo.git

# Extract owner/repo (bash regex)
if [[ $remote_url =~ github\.com[:/]([^/]+/[^/]+?)(\.git)?$ ]]; then
  owner_repo="${BASH_REMATCH[1]}"  # Returns: "owner/repo"
fi
```

**Codespace Querying**:
```bash
gh codespace list --json name,repository,state
# Returns JSON with repository.fullName = "owner/repo"
```

**Matching Process**:
1. Get local repo origin → extract `owner/repo`
2. Query Codespaces → get `repository.fullName` for each
3. Match where local `owner/repo` == Codespace `repository.fullName`
4. Calculate workspace path: `/workspaces/{repo-name}` (just repo name, not owner)

**Existing Patterns in Codebase**:
- `cleanup-branches:46` - Regex pattern to extract owner/repo from remote URL
- `codespace-ssh:61-65` - Query Codespaces with repository metadata
- `codespaces/tasks/main.yml:276` - Glob `/workspaces/*` to discover workspaces
- Handles both SSH (`git@github.com:owner/repo.git`) and HTTPS formats

**Codespace Clone Paths**:
- Work repositories: `/workspaces/{repo-name}` (just name, not owner/repo)
- Bootstrap repo: `~/new-machine-bootstrap` (different location, for provisioning)

#### Bidirectional Sync Tools

**Mutagen** (Recommended):
- Modern Go-based tool designed for remote development
- Real-time bidirectional sync with file watching
- SSH integration using existing config
- Conflict detection with multiple resolution modes
- Installation: `brew install mutagen-io/mutagen/mutagen`
- Command: `mutagen sync create --name=project ~/local remote:/remote`
- Modes: `two-way-safe` (manual conflict resolution), `two-way-resolved` (auto-resolve)

**rclone bisync** (Alternative):
- Mature tool, bisync is beta but production-ready
- Manual/scheduled sync (not real-time)
- Advanced conflict resolution: newer/older/larger/smaller/none
- SFTP/SSH support built-in
- Command: `rclone bisync /local remote:/remote --conflict-resolve newer`
- Filters file for exclusions

**Unison** (Mature, Stable):
- Long-established (1990s) bidirectional sync
- Interactive conflict resolution
- Requires same version on both machines (version compatibility issues)
- Manual sync runs (not real-time)
- SSH support via `root = ssh://user@host//path` in config file

**gh codespace cp** (Limited):
- Built-in GitHub CLI tool
- One-time copy only (not continuous sync)
- Command: `gh codespace cp -r ./local remote:/path`
- NOT suitable for continuous bidirectional sync

**fswatch + rsync** (Pseudo-bidirectional):
- File watching (fswatch on macOS, inotifywait on Linux) + rsync
- Can run watch scripts on both sides for pseudo-bidirectional
- Risk: Infinite loops, race conditions, no real conflict detection
- Better for unidirectional real-time sync

**Key Findings**:
- rsync alone is fundamentally unidirectional
- True bidirectional requires specialized tools (Mutagen, rclone bisync, Unison)
- All tools require manual ignore patterns (`.git`, `.claude`, `node_modules`, etc.)
- Conflict resolution trade-off: automatic (risk data loss) vs. manual (interrupts workflow)

### Architecture Implications

**Current State**:
- `.coding-agent` explicitly excluded from bootstrap sync (`bin/sync-to-codespace:106`)
- No mechanism exists for syncing arbitrary codebase `.coding-agent` directories
- Bootstrap repo sync is separate from workspace repository workflows

**Required Changes for User Requirements**:
- Need separate sync mechanism from bootstrap provisioning
- Must detect matching repositories by git origin
- Must handle bidirectional sync with conflict detection
- Must trigger on SSH disconnect (PAM) or fallback to periodic/manual
- Must sync workspace `.coding-agent` dirs, not bootstrap `.coding-agent`

**Complexity Factors**:
- PAM configuration requires root access in Codespace
- Git origin matching works only for GitHub repositories
- Conflict detection requires state tracking between syncs
- SSH disconnect hooks have reliability limitations

## Open Questions (Original)

1. **Scope**: Should sync handle only the bootstrap repo's `.coding-agent`, or all codebases with `.coding-agent` directories?
   - **Answer**: All codebases with same git origin

2. **Directionality**: Is bidirectional sync needed (Codespace → local), or only local → Codespace?
   - **Answer**: Bidirectional required

3. **Triggering**: Should sync be:
   - Manual (on-demand via command)
   - Automatic (on file change)
   - Periodic (scheduled)
   - On provision (integrated into `bin/sync-to-codespace`)
   - **Answer**: Automatic on disconnect preferred, periodic/manual acceptable

4. **Destination**: Where should synced files go in Codespace?
   - Same location (`~/new-machine-bootstrap/.coding-agent/`)
   - Workspace directory (`/workspaces/some-repo/.coding-agent/`)
   - Separate storage location
   - **Answer**: Workspace directory

5. **Conflict Resolution**: How to handle conflicts when same file modified in both locations?
   - **Answer**: Error and notify user (no auto-resolution)

6. **Implementation Approach**: Should this be:
   - Integrated into existing `bin/sync-to-codespace` script
   - New separate sync mechanism
   - Ansible-based sync task
   - Git-based synchronization (commit/push/pull)
   - Cloud storage synchronization (Dropbox, etc.)
   - **Research complete**: Options documented above (Mutagen, rclone bisync, Unison, PAM hooks, shell wrappers)
