# .coding-agent Directory Sync Implementation Plan

## Overview

Implement bidirectional synchronization of `.coding-agent` directories between local machines and GitHub Codespaces. The sync will be integrated into existing Codespace workflow scripts, using rsync for simple, reliable file transfers with no deletions or overwrites.

## Current State Analysis

### Existing Sync Mechanism
**Location**: `bin/sync-to-codespace:106`

Current implementation:
- Uses tar+ssh pipeline for bootstrap repository sync
- **Explicitly excludes** `.coding-agent`, `.claude`, and `.git` directories
- Unidirectional: local → Codespace only
- Scoped to bootstrap repo (`~/new-machine-bootstrap`)

```ruby
tar_cmd = "tar czf - --no-xattrs --exclude='.git' --exclude='.coding-agent' --exclude='.claude' ..."
```

### Repository Matching Patterns
**Location**: `cleanup-branches:46` (git origin parsing)

```ruby
owner_repo = remote_url[%r{[:/]([^/]+/[^/]+?)(\.git)?$}, 1]
```

**Location**: `codespace-ssh:61-65` (Codespace querying)

```ruby
codespaces_json = run_command('gh codespace list --json name,repository,state', ...)
codespaces = JSON.parse(codespaces_json)
```

### Key Discoveries:
- Git origin parsing regex handles both SSH and HTTPS formats
- Codespace queries return `repository.fullName` (owner/repo format)
- Workspace paths are `/workspaces/{repo-name}` (just name, not owner)
- Existing scripts use Ruby with `Open3.capture3` for command execution
- Error handling pattern: check `status.success?`, print stderr, exit 1

## Desired End State

Users can work seamlessly with `.coding-agent` directories across local and Codespace environments:

1. When creating a Codespace (`codespace-create`):
   - Local `.coding-agent/` syncs to Codespace `/workspaces/repo/.coding-agent/`
   - Only if local repo's git origin matches the Codespace repository

2. When disconnecting from SSH (`codespace-ssh`):
   - Codespace `.coding-agent/` syncs back to local repo
   - Shell wrapper function runs sync after SSH session ends
   - Only new/modified files are copied (never delete or overwrite)

3. Verification:
   - Files created in either location appear in both
   - No files are ever deleted by sync operations
   - Conflicts result in error messages (no auto-resolution)

## What We're NOT Doing

- No continuous/background sync while connected
- No automatic conflict resolution (user must resolve manually)
- No syncing of other directories (`.git`, `.claude`, etc.)
- No support for non-GitHub repositories
- No bidirectional simultaneous sync (always unidirectional per operation)
- No sync for bootstrap repository's `.coding-agent` (only workspace repos)

## Implementation Approach

### Strategy
Use rsync with `--ignore-existing` flag for append-only syncs:
- **Codespace creation**: rsync from current directory to `/workspaces/{repo-name}/.coding-agent/`
- **SSH disconnect**: rsync from `/workspaces/{repo-name}/.coding-agent/` to current directory
- Both operations preserve existing files (never overwrite/delete)

### Simple Logic
- **codespace-create**: We already know the repository from `--repo` argument, just extract repo name and sync
- **codespace-ssh**: We already know the codespace name, query it to get repository name and sync back
- **No complex matching needed**: Just use the information we already have

### Shell Wrapper Integration
Wrap the `gh codespace ssh` call in `codespace-ssh` script with Ruby block that runs sync after SSH exits.

## Phase 1: Create Rsync Wrapper Module

### Overview
Create a simple Ruby module that wraps rsync operations for syncing `.coding-agent` directories with append-only behavior.

### Changes Required:

#### 1. Create `lib/coding_agent_syncer.rb`
**File**: `lib/coding_agent_syncer.rb` (new file)
**Purpose**: Rsync wrapper for .coding-agent directory sync

```ruby
# frozen_string_literal: true

require 'open3'
require 'fileutils'

module CodingAgentSyncer
  class SyncError < StandardError; end

  class << self
    # Sync .coding-agent from local to Codespace
    # source: local directory path (must contain .coding-agent/)
    # codespace_name: name of target Codespace
    # remote_path: absolute path to workspace directory in Codespace
    def sync_to_codespace(source_dir, codespace_name, remote_path)
      local_path = File.join(source_dir, '.coding-agent/')

      unless Dir.exist?(local_path)
        puts "No .coding-agent directory found at #{local_path}, skipping sync"
        return true
      end

      remote_target = "#{remote_path}/"

      puts "\n==> Syncing .coding-agent to Codespace..."
      puts "    Local: #{local_path}"
      puts "    Remote: #{codespace_name}:#{remote_target}"

      # Create remote directory first
      create_cmd = "gh codespace ssh -c #{codespace_name} -- 'mkdir -p #{remote_path}'"
      system(create_cmd)

      unless $?.success?
        raise SyncError, "Failed to create remote directory: #{remote_path}"
      end

      # Rsync with append-only behavior
      rsync_cmd = [
        'rsync',
        '-az',                           # archive mode, compress
        '--ignore-existing',             # skip files that exist on receiver
        '-e', "gh codespace ssh -c #{codespace_name} --",
        local_path,
        "remote:#{remote_target}"
      ].join(' ')

      stdout, stderr, status = Open3.capture3(rsync_cmd)

      unless status.success?
        $stderr.puts "Error: Failed to sync to Codespace"
        $stderr.puts stderr unless stderr.empty?
        raise SyncError, "Rsync failed with exit code #{status.exitstatus}"
      end

      puts "==> Sync to Codespace complete!"
      true
    end

    # Sync .coding-agent from Codespace back to local
    # dest_dir: local directory path (will create .coding-agent/ if needed)
    # codespace_name: name of source Codespace
    # remote_path: absolute path to .coding-agent in Codespace
    def sync_from_codespace(dest_dir, codespace_name, remote_path)
      # Ensure local .coding-agent directory exists
      local_path = File.join(dest_dir, '.coding-agent/')
      FileUtils.mkdir_p(local_path)

      puts "\n==> Syncing .coding-agent from Codespace..."
      puts "    Remote: #{codespace_name}:#{remote_path}/"
      puts "    Local: #{local_path}"

      # Check if remote directory exists
      check_cmd = "gh codespace ssh -c #{codespace_name} -- 'test -d #{remote_path}'"
      system(check_cmd)

      unless $?.success?
        puts "No .coding-agent directory found in Codespace, skipping sync"
        return true
      end

      # Rsync with append-only behavior
      rsync_cmd = [
        'rsync',
        '-az',                           # archive mode, compress
        '--ignore-existing',             # skip files that exist on receiver
        '-e', "gh codespace ssh -c #{codespace_name} --",
        "remote:#{remote_path}/",
        local_path
      ].join(' ')

      stdout, stderr, status = Open3.capture3(rsync_cmd)

      unless status.success?
        $stderr.puts "Error: Failed to sync from Codespace"
        $stderr.puts stderr unless stderr.empty?
        raise SyncError, "Rsync failed with exit code #{status.exitstatus}"
      end

      puts "==> Sync from Codespace complete!"
      true
    end
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] File exists: `test -f lib/coding_agent_syncer.rb`
- [x] Ruby syntax is valid: `ruby -c lib/coding_agent_syncer.rb`
- [x] Module can be required: `ruby -e "require_relative 'lib/coding_agent_syncer'"`
- [x] rsync command is available: `command -v rsync`

#### Manual Verification:
- [ ] Create test file locally, sync to Codespace, verify file appears
- [ ] Create test file in Codespace, sync back, verify file appears locally
- [ ] Modify file locally, run sync, verify remote file is NOT overwritten
- [ ] Sync with no `.coding-agent` directory prints skip message and succeeds

---

## Phase 2: Integrate Sync into codespace-create

### Overview
Add `.coding-agent` sync to the Codespace creation workflow, running after provisioning completes.

### Changes Required:

#### 1. Update `bin/codespace-create`
**File**: `bin/codespace-create`
**Changes**: Add sync logic after provisioning

**After line 7** (after `SCRIPT_DIR` definition), add require:
```ruby
require_relative '../lib/coding_agent_syncer'
```

**Replace lines 148-157** (provisioning section) with:
```ruby
  # Run sync-to-codespace with the codespace name
  puts "\n==> Running provisioning..."

  sync_script = File.join(SCRIPT_DIR, 'bin', 'sync-to-codespace')

  unless system(sync_script, codespace_name)
    puts "\nError: Provisioning failed"
    puts "You can retry with: #{sync_script} #{codespace_name}"
    exit 1
  end

  puts "\n==> Provisioning complete!"

  # Sync .coding-agent directory from current directory
  sync_coding_agent_to_codespace(codespace_name, repository)

  puts "\n==> Done! Your Codespace is ready."
  puts "\nTo connect, run:"
  puts "  codespace-ssh #{codespace_name}"
```

**Before the `main` function** (after helper functions), add:
```ruby
def sync_coding_agent_to_codespace(codespace_name, repository)
  # Skip if no .coding-agent directory in current directory
  local_path = File.join(Dir.pwd, '.coding-agent')
  unless Dir.exist?(local_path)
    return
  end

  # Extract repo name from repository argument (format: "owner/repo")
  repo_name = repository.split('/').last
  remote_path = "/workspaces/#{repo_name}/.coding-agent"

  # Perform sync
  begin
    CodingAgentSyncer.sync_to_codespace(Dir.pwd, codespace_name, remote_path)
  rescue CodingAgentSyncer::SyncError => e
    puts "\nWarning: Failed to sync .coding-agent directory"
    puts e.message
    puts "You can manually sync later with: bin/sync-coding-agent --to-codespace"
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] Ruby syntax is valid: `ruby -c bin/codespace-create`
- [x] Script prints help: `bin/codespace-create --help`
- [x] Required module can be loaded: `ruby -e "require_relative 'lib/coding_agent_syncer'"`

#### Manual Verification:
- [ ] From repo directory with `.coding-agent/`, `codespace-create` syncs files to Codespace
- [ ] From directory without `.coding-agent/`, `codespace-create` skips sync silently
- [ ] Files in local `.coding-agent/` appear in Codespace `/workspaces/repo/.coding-agent/`
- [ ] If sync fails, script prints warning but continues (doesn't exit)

---

## Phase 3: Integrate Sync into codespace-ssh

### Overview
Wrap the SSH connection with sync logic that runs after disconnection, using a Ruby approach to ensure the sync command executes after SSH session ends.

### Changes Required:

#### 1. Update `bin/codespace-ssh`
**File**: `bin/codespace-ssh`
**Changes**: Add sync-on-disconnect logic

**After line 6** (after `require 'open3'`), add require:
```ruby
require_relative '../lib/coding_agent_syncer'
```

**Replace lines 113-118** (final SSH connection) with:
```ruby
  puts ""
  puts "==> Connecting to Codespace: #{codespace_name}"
  puts ""

  # Execute SSH connection
  system("gh codespace ssh -c #{codespace_name}")
  ssh_exit_code = $?.exitstatus

  # Sync .coding-agent back to local after disconnect
  sync_coding_agent_from_codespace(codespace_name)

  exit ssh_exit_code
```

**Before the `main` function**, add:
```ruby
def sync_coding_agent_from_codespace(codespace_name)
  puts "\n==> Disconnected from Codespace"

  # Skip if no .coding-agent directory in current directory
  local_path = File.join(Dir.pwd, '.coding-agent')
  unless Dir.exist?(local_path)
    return
  end

  # Query Codespace to get repository info
  stdout, stderr, status = Open3.capture3("gh codespace list --json name,repository --jq '.[] | select(.name==\"#{codespace_name}\")'")

  unless status.success?
    puts "Warning: Could not query Codespace information"
    return
  end

  begin
    codespace_info = JSON.parse(stdout)
    repo_full_name = codespace_info.dig('repository', 'fullName')

    unless repo_full_name
      puts "Warning: Could not determine Codespace repository"
      return
    end

    # Extract just repo name (not owner)
    repo_name = repo_full_name.split('/').last
    remote_path = "/workspaces/#{repo_name}/.coding-agent"

    # Perform sync
    CodingAgentSyncer.sync_from_codespace(Dir.pwd, codespace_name, remote_path)
  rescue JSON::ParserError => e
    puts "Warning: Could not parse Codespace information"
  rescue CodingAgentSyncer::SyncError => e
    puts "\nWarning: Failed to sync .coding-agent directory from Codespace"
    puts e.message
    puts "You can manually sync later with: bin/sync-coding-agent --from-codespace"
  rescue StandardError => e
    puts "\nWarning: Unexpected error during sync: #{e.message}"
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] Ruby syntax is valid: `ruby -c bin/codespace-ssh`
- [x] Script can list Codespaces: `bin/codespace-ssh` (when no Codespaces available)
- [x] Required module can be loaded: `ruby -e "require_relative 'lib/coding_agent_syncer'"`

#### Manual Verification:
- [ ] Connect to Codespace, create file in `/workspaces/repo/.coding-agent/`, disconnect
- [ ] File appears in local `.coding-agent/` directory after disconnect
- [ ] Disconnect from directory with `.coding-agent/` syncs files back
- [ ] Disconnect from directory without `.coding-agent/` skips sync silently
- [ ] SSH exit code is preserved (check with `echo $?` after disconnect)
- [ ] Sync errors print warnings but don't prevent disconnection

---

## Phase 4: Add Manual Sync Command

### Overview
Create a standalone sync command for manual synchronization when needed.

### Changes Required:

#### 1. Create `bin/sync-coding-agent`
**File**: `bin/sync-coding-agent` (new file)
**Purpose**: Manual sync command for troubleshooting and special cases

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'

SCRIPT_DIR = File.expand_path('..', __dir__)
require_relative File.join(SCRIPT_DIR, 'lib', 'coding_agent_syncer')

def find_codespace_for_repo(repo_name)
  # Query all available Codespaces
  stdout, stderr, status = Open3.capture3("gh codespace list --json name,repository,state")

  unless status.success?
    $stderr.puts "Error: Failed to list Codespaces"
    $stderr.puts stderr unless stderr.empty?
    exit 1
  end

  codespaces = JSON.parse(stdout)
    .select { |cs| cs['state'] == 'Available' }
    .select { |cs| cs.dig('repository', 'fullName')&.end_with?("/#{repo_name}") }

  if codespaces.empty?
    $stderr.puts "Error: No available Codespace found for repository ending with '/#{repo_name}'"
    exit 1
  end

  if codespaces.size > 1
    $stderr.puts "Error: Multiple Codespaces found for this repository:"
    codespaces.each { |cs| $stderr.puts "  - #{cs['name']}" }
    $stderr.puts "\nPlease specify which one: bin/sync-coding-agent DIRECTION CODESPACE_NAME"
    exit 1
  end

  codespaces.first['name']
end

def main
  direction = nil
  codespace_name = nil

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: bin/sync-coding-agent [--to-codespace | --from-codespace] [CODESPACE_NAME]"
    opts.separator ""
    opts.separator "Manually sync .coding-agent directory between local and Codespace"
    opts.separator ""
    opts.separator "Options:"

    opts.on("--to-codespace", "Sync from local to Codespace") do
      direction = :to_codespace
    end

    opts.on("--from-codespace", "Sync from Codespace to local") do
      direction = :from_codespace
    end

    opts.separator ""
    opts.separator "Arguments:"
    opts.separator "  CODESPACE_NAME    Optional. If not provided, will find Codespace for current directory"
    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  bin/sync-coding-agent --to-codespace"
    opts.separator "  bin/sync-coding-agent --from-codespace my-codespace-name"

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end

  begin
    parser.parse!
    codespace_name = ARGV[0]
  rescue OptionParser::InvalidOption => e
    puts "Error: #{e.message}"
    puts ""
    puts parser
    exit 1
  end

  unless direction
    puts "Error: Must specify --to-codespace or --from-codespace"
    puts ""
    puts parser
    exit 1
  end

  # Check for .coding-agent directory
  local_path = File.join(Dir.pwd, '.coding-agent')
  unless Dir.exist?(local_path)
    puts "Error: No .coding-agent directory in current directory"
    exit 1
  end

  # If no codespace name provided, try to find one based on current directory name
  unless codespace_name
    repo_name = File.basename(Dir.pwd)
    codespace_name = find_codespace_for_repo(repo_name)
  end

  puts "==> Using Codespace: #{codespace_name}"

  # Query Codespace to get repository info
  stdout, stderr, status = Open3.capture3("gh codespace list --json name,repository --jq '.[] | select(.name==\"#{codespace_name}\")'")

  unless status.success?
    $stderr.puts "Error: Could not query Codespace information"
    $stderr.puts stderr unless stderr.empty?
    exit 1
  end

  begin
    codespace_info = JSON.parse(stdout)
    repo_full_name = codespace_info.dig('repository', 'fullName')

    unless repo_full_name
      $stderr.puts "Error: Could not determine Codespace repository"
      exit 1
    end

    repo_name = repo_full_name.split('/').last
    remote_path = "/workspaces/#{repo_name}/.coding-agent"

    puts "    Repository: #{repo_full_name}"
    puts "    Workspace: /workspaces/#{repo_name}"

    # Perform sync
    case direction
    when :to_codespace
      CodingAgentSyncer.sync_to_codespace(Dir.pwd, codespace_name, remote_path)
    when :from_codespace
      CodingAgentSyncer.sync_from_codespace(Dir.pwd, codespace_name, remote_path)
    end
  rescue JSON::ParserError => e
    $stderr.puts "Error: Could not parse Codespace information"
    exit 1
  rescue CodingAgentSyncer::SyncError => e
    $stderr.puts "\nError: Sync failed"
    $stderr.puts e.message
    exit 1
  end

  puts "\n==> Done!"
end

main
```

**After creating the file**, make it executable:
```bash
chmod +x bin/sync-coding-agent
```

### Success Criteria:

#### Automated Verification:
- [x] File is executable: `test -x bin/sync-coding-agent`
- [x] Ruby syntax is valid: `ruby -c bin/sync-coding-agent`
- [x] Help text displays: `bin/sync-coding-agent --help`

#### Manual Verification:
- [ ] `bin/sync-coding-agent --to-codespace` syncs local → Codespace
- [ ] `bin/sync-coding-agent --from-codespace` syncs Codespace → local
- [ ] Command auto-detects Codespace based on current directory name
- [ ] Command accepts explicit Codespace name as argument
- [ ] Error messages are clear when no `.coding-agent` directory or no match found

---

## Phase 5: Update Documentation

### Overview
Update CLAUDE.md with information about the new sync functionality.

### Changes Required:

#### 1. Update `CLAUDE.md`
**File**: `CLAUDE.md`
**Changes**: Document sync behavior in relevant sections

**In the "Codespaces Workflow" section** (around line 132), update the examples:

```markdown
**Codespaces Workflow**:
```bash
# Create a new Codespace and provision it:
bin/codespace-create --repo REPOSITORY --machine MACHINE_TYPE --branch BRANCH
# Example: bin/codespace-create --repo f1sherman/new-machine-bootstrap --machine premiumLinux --branch main
# Note: If run from matching repository directory, syncs .coding-agent/ to Codespace

# Connect to existing Codespace:
bin/codespace-ssh [codespace-name]
# Auto-selects if only one available, uses fzf if multiple
# Note: Syncs .coding-agent/ back to local on disconnect (if in matching repo directory)

# Re-provision existing Codespace (e.g., after making changes to bootstrap repo):
bin/sync-to-codespace
# Syncs bootstrap repo and re-runs provisioning

# Manual .coding-agent sync (if needed):
bin/sync-coding-agent --to-codespace      # Local → Codespace
bin/sync-coding-agent --from-codespace    # Codespace → Local
```
```

**Add new section after "Codespaces Workflow"**:

```markdown
### .coding-agent Directory Sync

The `.coding-agent` directories (containing plans and research documents) are automatically synced between local and Codespaces:

**Sync Behavior**:
- **On Codespace creation**: Local `.coding-agent/` → Codespace `/workspaces/repo/.coding-agent/`
- **On SSH disconnect**: Codespace `.coding-agent/` → Local `.coding-agent/`
- **Append-only**: Only new files are copied, existing files are never overwritten or deleted
- **Repository matching**: Only syncs when local repo's git origin matches Codespace repository

**Requirements**:
- Must run commands from the repository directory (not bootstrap directory)
- Repository must have GitHub as remote origin
- Matching Codespace must be available
- rsync must be installed (available by default on macOS and Codespaces)

**Manual Sync**:
If automatic sync fails or you need to sync manually:
```bash
cd /path/to/repository
bin/sync-coding-agent --to-codespace      # Upload to Codespace
bin/sync-coding-agent --from-codespace    # Download from Codespace
```

**Conflict Handling**:
The sync is designed to be append-only to avoid conflicts. If you modify the same file in both locations:
- The existing version is preserved (not overwritten)
- You'll need to manually reconcile differences
- Consider deleting one version before syncing to let the other copy over
```

### Success Criteria:

#### Automated Verification:
- [x] CLAUDE.md syntax is valid Markdown
- [x] File can be rendered: `cat CLAUDE.md` (check for formatting issues)

#### Manual Verification:
- [ ] Documentation accurately describes sync behavior
- [ ] Code examples are correct and match actual command syntax
- [ ] Conflict handling guidance is clear
- [ ] Requirements section is complete

---

## Testing Strategy

### Unit Tests:
No formal unit tests initially, but manual testing should cover:
- Repository matching logic (both SSH and HTTPS git URLs)
- Codespace querying and filtering
- Path calculation for workspace directories
- Rsync command construction

### Integration Tests:
Test complete workflows end-to-end:

1. **Create Codespace from matching repo**:
   ```bash
   cd ~/projects/new-machine-bootstrap
   echo "test content" > .coding-agent/test-sync.md
   bin/codespace-create --repo f1sherman/new-machine-bootstrap --machine premiumLinux --branch main
   # SSH to Codespace, verify /workspaces/new-machine-bootstrap/.coding-agent/test-sync.md exists
   ```

2. **Connect and modify in Codespace**:
   ```bash
   cd ~/projects/new-machine-bootstrap
   bin/codespace-ssh [name]
   # In Codespace: echo "created in codespace" > /workspaces/new-machine-bootstrap/.coding-agent/codespace-file.md
   # Exit SSH
   # Verify ~/projects/new-machine-bootstrap/.coding-agent/codespace-file.md exists locally
   ```

3. **Append-only behavior**:
   ```bash
   echo "local version" > .coding-agent/conflict-test.md
   bin/sync-coding-agent --to-codespace
   # In Codespace: modify /workspaces/repo/.coding-agent/conflict-test.md
   bin/sync-coding-agent --from-codespace
   # Local file should NOT be overwritten (still contains "local version")
   ```

4. **Non-matching repository**:
   ```bash
   cd ~/projects/different-repo
   bin/codespace-ssh [name]
   # Should skip sync with message
   ```

5. **No .coding-agent directory**:
   ```bash
   cd ~/projects/new-repo-without-coding-agent
   bin/sync-coding-agent --to-codespace
   # Should print "No .coding-agent directory found, skipping sync"
   ```

### Manual Testing Steps:
1. Create `.coding-agent/plans/test-plan.md` locally
2. Run `codespace-create` from repository directory
3. SSH to Codespace, verify file exists in workspace
4. Create new file in Codespace `.coding-agent/research/test.md`
5. Disconnect from SSH
6. Verify new file appears in local `.coding-agent/research/`
7. Modify file in both locations
8. Run manual sync, verify neither is overwritten
9. Test from non-matching directory, verify skip message
10. Test manual sync command with both `--to-codespace` and `--from-codespace`

## Performance Considerations

- **Rsync efficiency**: Only transfers new/changed files (uses timestamps)
- **Compression**: `-z` flag compresses data during transfer
- **No full scans**: Rsync doesn't scan entire filesystems, only specified directories
- **SSH overhead**: `gh codespace ssh` adds minimal overhead vs direct SSH
- **Typical sync time**: < 5 seconds for small `.coding-agent` directories (few MB)

## Migration Notes

No migration needed - this is a new feature. However:

1. **Existing `.coding-agent` directories**: Will remain in place, sync will start working immediately
2. **Bootstrap repository exclusion**: Remains unchanged (still excluded from `sync-to-codespace`)
3. **Backward compatibility**: All existing scripts continue to work without changes
4. **Optional adoption**: Users can ignore sync by running commands from non-matching directories

## References

- Research document: `.coding-agent/research/2025-11-17-coding-agent-sync-mechanisms.md`
- Existing git parsing: `cleanup-branches:46`
- Existing Codespace query: `codespace-ssh:61-65`
- Existing sync mechanism: `bin/sync-to-codespace:106`
- Workspace discovery: `roles/codespaces/tasks/main.yml:276`
