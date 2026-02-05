# Claude Session Sync Implementation Plan

## Overview

Implement bidirectional synchronization of Claude Code sessions between local machines and GitHub Codespaces, using a "newer timestamp wins" strategy to safely handle sessions that may be continued in either environment.

## Plan Metadata

- Date: 2026-02-05 09:20:54 CST
- Git Commit: 9da6cba959de930b909ff441c6ae47c22a243f2f
- Branch: main
- Repository: new-machine-bootstrap

## Motivation

When working in Codespaces, Claude Code sessions started locally are not available, and sessions created in Codespaces are lost when the Codespace is deleted. This creates friction when switching between environments and risks losing valuable conversation history.

### Relevant Artifacts
- Existing sync plan: `.coding-agent/plans/2025-11-17-coding-agent-sync.md`
- Sync module: `lib/dev_env_syncer.rb`
- Session management: `roles/common/files/bin/list-claude-sessions`

## Current State Analysis

### Session Storage Structure
- **Location**: `~/.claude/projects/<path-encoded-directory>/`
- **Path encoding**: `/Users/brianjohn/projects/repo` → `-Users-brianjohn-projects-repo`
- **Codespace path**: `/workspaces/repo` → `-workspaces-repo`
- **Session files**: `<uuid>.jsonl` (append-only JSON Lines format)
- **Associated directories**: `<uuid>/` containing:
  - `subagents/` - Sub-agent transcripts
  - `tool-results/` - Large tool output files

### Existing Infrastructure
- `lib/dev_env_syncer.rb:125-148` - Repository matching via `repositories_match?` and `normalize_github_repo`
- `bin/codespace-create:54-65` - Calls `DevEnvSyncer.sync_to_codespace` after provisioning
- `bin/codespace-ssh:51-79` - Calls `DevEnvSyncer.sync_from_codespace` on disconnect
- `roles/common/files/bin/list-claude-sessions` - Lists sessions with `--days` filter

### Key Insight: Newer Timestamp Wins
Each message in a `.jsonl` session file has a `timestamp` field. The file with the more recent last-message timestamp is definitively the more current version. This approach is robust even if Claude Code ever compacts or truncates sessions:
- If local has newer last timestamp → local was used more recently → use local
- If remote has newer last timestamp → remote was used more recently → use remote
- If same timestamp → files are identical → no sync needed

## Requirements

1. **Push to Codespace**: On `codespace-create` and `sync-to-codespace`, sync recent local sessions to Codespace
2. **Pull from Codespace**: On `codespace-ssh` disconnect, sync updated sessions back to local
3. **Session filtering**: Only sync sessions modified in the last 7 days
4. **Repository matching**: Only sync sessions for matching repositories (reuse existing logic)
5. **Conflict resolution**: Use "larger file wins" - the larger `.jsonl` file contains more conversation history
6. **Complete session sync**: Include associated directories (subagents, tool-results)

## Non-Goals

- Real-time sync while connected (only sync on connect/disconnect)
- Syncing sessions older than 7 days
- Syncing sessions for non-matching repositories
- Manual merge of conflicting sessions (larger wins automatically)
- Syncing other Claude data (settings, history, etc.)

## Proposed Approach

### Path Mapping Strategy

Map between local and Codespace project directories using the repository name:

```
Local:     ~/.claude/projects/-Users-brianjohn-projects-product/
Codespace: ~/.claude/projects/-workspaces-product/
```

The repository name (`product`) is extracted from:
- Local: Last component of the working directory path
- Codespace: Repository name from `gh codespace list --json repository`

### Sync Algorithm

```
For each session file modified in last 7 days:
  1. Check if corresponding file exists in destination
  2. If not exists: copy file and associated directory
  3. If exists: compare last-message timestamps
     - Source newer: copy source to destination (overwrite)
     - Destination newer or equal: skip (destination is more current)
  4. For associated directories: sync all contents (subagents, tool-results)
```

### Integration Points

1. **`codespace-create`**: After provisioning, call new session sync function
2. **`sync-to-codespace`**: Add session sync after repository sync
3. **`codespace-ssh`**: On disconnect, call session sync in reverse direction
4. **`sync-dev-env`**: Add `--sessions` flag for manual session sync

### Alternatives Considered

- **File size comparison** - Rejected: Would break if Claude Code ever compacts/truncates sessions
- **mtime-based sync** - Rejected: SSH transfer may alter modification times, making comparison unreliable
- **Hash-based comparison** - Rejected: Requires reading full file contents; timestamp comparison is simpler
- **Rsync with --update** - Rejected: Uses mtime which can be unreliable across transfers

## Implementation Plan

### Phase 1: Create Session Sync Module

Create `lib/claude_session_syncer.rb` with core sync logic:

- [x] `find_project_dir(repo_name)` - Find local project directory by repo name
- [x] `find_recent_sessions(project_dir, days: 7)` - List sessions modified in last N days
- [x] `get_last_timestamp(file_path)` - Extract timestamp from last message in session file
- [x] `get_remote_last_timestamp(codespace_name, file_path)` - Same but for remote file
- [x] `sync_session_to_codespace(session_path, codespace_name, remote_project_dir)` - Sync single session with newer-wins logic
- [x] `sync_session_from_codespace(session_path, codespace_name, local_project_dir)` - Reverse sync
- [x] `sync_sessions_to_codespace(repo_name, codespace_name, days: 7)` - High-level push function
- [x] `sync_sessions_from_codespace(repo_name, codespace_name, days: 7)` - High-level pull function

### Phase 2: Integrate with codespace-create

- [x] Add `require_relative '../lib/claude_session_syncer'`
- [x] Call `ClaudeSessionSyncer.sync_sessions_to_codespace` after `sync_dev_env_to_codespace`
- [x] Handle errors gracefully (warn but don't fail creation)

### Phase 3: Integrate with sync-to-codespace

- [x] Add session sync option (enabled by default)
- [x] Call session sync after repository provisioning completes
- [x] Support `--no-sessions` flag to skip session sync

### Phase 4: Integrate with codespace-ssh

- [x] Call `ClaudeSessionSyncer.sync_sessions_from_codespace` in `sync_coding_agent_back`
- [x] Only sync if repository matches (reuse existing check)
- [x] Handle errors gracefully (warn but preserve SSH exit code)

### Phase 5: Add Manual Sync Command

- [x] Add `--sessions` flag to `bin/sync-dev-env`
- [x] Support `--sessions-only` for syncing just sessions
- [x] Add `--days N` option to override 7-day default

### Phase 6: Sync on Connect

Update `codespace-ssh` to sync bidirectionally before starting the SSH session:

- [x] Pull sessions from Codespace before connecting (recovers work from previous timeouts)
- [x] Push local sessions to Codespace before connecting
- [x] Keep existing pull-on-disconnect behavior

This ensures that even if a previous session timed out, you recover those sessions on next connect.

### Phase 7: Scheduled Background Sync (Work Machines Only)

Create a launchd job that runs hourly to pull sessions from all running Codespaces:

- [x] Create `bin/sync-sessions-from-all-codespaces` script
- [x] Create `roles/macos/templates/launchd/com.user.claude-session-sync.plist`
- [x] Add Ansible task to install plist (work machines only, via `bootstrap_use == 'work'`)
- [x] Log to `~/Library/Logs/claude-session-sync.log`

**Script behavior:**
- Query `gh codespace list` for all "Available" (running) Codespaces
- For each running Codespace, do bidirectional sync (pull first, then push)
- Silent/no-op when no Codespaces are running
- Uses newer-timestamp-wins strategy for safe conflict resolution

**Schedule:** Every hour (Codespace timeout is 4 hours, so 3+ sync opportunities)

### Phase 8: Update Documentation

- [x] Document session sync in CLAUDE.md
- [x] Explain newer-timestamp-wins conflict resolution
- [x] Document `--sessions` and `--days` options
- [x] Document background sync (work machines only)

## Testing Strategy

### Automated Verification
- [x] `ruby -c lib/claude_session_syncer.rb` - Syntax valid
- [x] `ruby -e "require_relative 'lib/claude_session_syncer'"` - Module loads
- [x] `bin/codespace-create --help` - Still works
- [x] `bin/sync-dev-env --help` - Shows new options

### Manual Verification
- [ ] Create session locally, create Codespace, verify session appears in Codespace
- [ ] Continue session in Codespace, disconnect, verify local session is updated
- [ ] Continue session locally after Codespace sync, verify local version preserved (larger)
- [ ] Verify sessions older than 7 days are not synced
- [ ] Verify sessions for non-matching repos are not synced
- [ ] Simulate timeout: work in Codespace, let it timeout, reconnect, verify session recovered
- [ ] Verify background sync runs hourly on work machine (check log file)
- [ ] Verify background sync does NOT run on personal machine

## Test Results

| Test | Status | Output |
| --- | --- | --- |
| `ruby -c lib/claude_session_syncer.rb` | ✅ Pass | Syntax OK |
| `ruby -e "require_relative 'lib/claude_session_syncer'"` | ✅ Pass | Module loads successfully |
| `bin/codespace-create --help` | ✅ Pass | Shows help without errors |
| `bin/sync-dev-env --help` | ✅ Pass | Shows new options |
| `ruby -c bin/sync-sessions-from-all-codespaces` | ✅ Pass | Syntax OK |
| `plutil -lint ~/Library/LaunchAgents/com.user.claude-session-sync.plist` | ⏳ Pending (requires provisioning) | |
| `launchctl list \| grep claude-session-sync` | ⏳ Pending (requires provisioning) | |

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Large sessions slow down sync | Filter to 7 days limits scope; parallel sync if needed later |
| Session file corruption during transfer | Use tar for atomic transfers; verify file size after transfer |
| Codespace deleted before sync-back | Sessions still exist locally; warn user to sync before deletion |
| Multiple Codespaces for same repo | Sync to/from selected Codespace only; user manages which to use |

## Open Questions

None - all questions resolved in discussion.

---

## Detailed Implementation

### Phase 1: lib/claude_session_syncer.rb

```ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'

module ClaudeSessionSyncer
  class SyncError < StandardError; end

  CLAUDE_PROJECTS_DIR = File.expand_path('~/.claude/projects')
  DEFAULT_DAYS = 7

  class << self
    # Find local project directory for a repository name
    # Searches ~/.claude/projects/ for directories ending with the repo name
    def find_local_project_dir(repo_name)
      return nil unless Dir.exist?(CLAUDE_PROJECTS_DIR)

      Dir.children(CLAUDE_PROJECTS_DIR).find do |dir|
        dir.end_with?("-#{repo_name}")
      end&.then { |dir| File.join(CLAUDE_PROJECTS_DIR, dir) }
    end

    # Get the remote project directory path for a Codespace
    def remote_project_dir(repo_name)
      "#{CLAUDE_PROJECTS_DIR}/-workspaces-#{repo_name}"
    end

    # Find session files modified within the last N days
    def find_recent_sessions(project_dir, days: DEFAULT_DAYS)
      return [] unless project_dir && Dir.exist?(project_dir)

      cutoff = Time.now - (days * 24 * 60 * 60)

      Dir.glob(File.join(project_dir, '*.jsonl')).select do |file|
        File.mtime(file) > cutoff
      end
    end

    # Get last message timestamp from a session file
    # Returns nil if file doesn't exist or has no valid timestamp
    def get_last_timestamp(file_path)
      return nil unless File.exist?(file_path)

      last_line = `tail -1 '#{file_path}' 2>/dev/null`.strip
      return nil if last_line.empty?

      data = JSON.parse(last_line)
      data['timestamp']
    rescue JSON::ParserError, StandardError
      nil
    end

    # Get last message timestamp from remote session file
    def get_remote_last_timestamp(codespace_name, remote_path)
      stdout, _stderr, status = Open3.capture3(
        "gh codespace ssh -c #{codespace_name} -- 'tail -1 \"#{remote_path}\" 2>/dev/null'"
      )
      return nil unless status.success?

      last_line = stdout.strip
      return nil if last_line.empty?

      data = JSON.parse(last_line)
      data['timestamp']
    rescue JSON::ParserError, StandardError
      nil
    end

    # Compare timestamps, returns true if ts1 is newer than ts2
    # nil timestamps are treated as oldest (missing file)
    def timestamp_newer?(ts1, ts2)
      return true if ts2.nil? && ts1
      return false if ts1.nil?
      ts1 > ts2
    end

    # Sync a single session file to Codespace (newer timestamp wins)
    def sync_session_to_codespace(local_session, codespace_name, remote_project_dir)
      session_id = File.basename(local_session, '.jsonl')
      remote_session = File.join(remote_project_dir, "#{session_id}.jsonl")

      local_ts = get_last_timestamp(local_session)
      remote_ts = get_remote_last_timestamp(codespace_name, remote_session)

      if timestamp_newer?(local_ts, remote_ts)
        # Local is newer (or remote doesn't exist) - push local
        ensure_remote_dir(codespace_name, remote_project_dir)
        transfer_to_codespace(local_session, codespace_name, remote_session)

        # Also sync associated directory if it exists
        local_dir = local_session.sub(/\.jsonl$/, '')
        if Dir.exist?(local_dir)
          remote_dir = remote_session.sub(/\.jsonl$/, '')
          sync_directory_to_codespace(local_dir, codespace_name, remote_dir)
        end

        :pushed
      else
        :skipped
      end
    end

    # Sync a single session file from Codespace (newer timestamp wins)
    def sync_session_from_codespace(remote_session, codespace_name, local_project_dir)
      session_id = File.basename(remote_session, '.jsonl')
      local_session = File.join(local_project_dir, "#{session_id}.jsonl")

      remote_ts = get_remote_last_timestamp(codespace_name, remote_session)
      local_ts = get_last_timestamp(local_session)

      if timestamp_newer?(remote_ts, local_ts)
        # Remote is newer (or local doesn't exist) - pull remote
        FileUtils.mkdir_p(local_project_dir)
        transfer_from_codespace(remote_session, codespace_name, local_session)

        # Also sync associated directory if it exists
        remote_dir = remote_session.sub(/\.jsonl$/, '')
        if remote_dir_exists?(codespace_name, remote_dir)
          local_dir = local_session.sub(/\.jsonl$/, '')
          sync_directory_from_codespace(remote_dir, codespace_name, local_dir)
        end

        :pulled
      else
        :skipped
      end
    end

    # High-level: sync all recent sessions to Codespace
    def sync_sessions_to_codespace(repo_name, codespace_name, days: DEFAULT_DAYS)
      local_dir = find_local_project_dir(repo_name)
      unless local_dir
        puts "    No local Claude sessions found for #{repo_name}"
        return { pushed: 0, skipped: 0 }
      end

      remote_dir = remote_project_dir(repo_name)
      sessions = find_recent_sessions(local_dir, days: days)

      if sessions.empty?
        puts "    No recent sessions to sync (last #{days} days)"
        return { pushed: 0, skipped: 0 }
      end

      puts "    Found #{sessions.length} session(s) from last #{days} days"

      results = { pushed: 0, skipped: 0 }
      sessions.each do |session|
        result = sync_session_to_codespace(session, codespace_name, remote_dir)
        results[result] += 1
      end

      puts "    Pushed: #{results[:pushed]}, Skipped: #{results[:skipped]}"
      results
    end

    # High-level: sync all recent sessions from Codespace
    def sync_sessions_from_codespace(repo_name, codespace_name, days: DEFAULT_DAYS)
      local_dir = find_local_project_dir(repo_name)
      remote_dir = remote_project_dir(repo_name)

      # List remote sessions
      sessions = find_remote_recent_sessions(codespace_name, remote_dir, days: days)

      if sessions.empty?
        puts "    No recent sessions in Codespace (last #{days} days)"
        return { pulled: 0, skipped: 0 }
      end

      puts "    Found #{sessions.length} session(s) in Codespace"

      # Ensure local project dir exists (may be first sync)
      target_dir = local_dir || File.join(CLAUDE_PROJECTS_DIR, "-workspaces-#{repo_name}")
      FileUtils.mkdir_p(target_dir)

      results = { pulled: 0, skipped: 0 }
      sessions.each do |session|
        result = sync_session_from_codespace(session, codespace_name, target_dir)
        results[result] += 1
      end

      puts "    Pulled: #{results[:pulled]}, Skipped: #{results[:skipped]}"
      results
    end

    private

    def ensure_remote_dir(codespace_name, remote_dir)
      system("gh codespace ssh -c #{codespace_name} -- 'mkdir -p \"#{remote_dir}\"' 2>/dev/null")
    end

    def remote_dir_exists?(codespace_name, remote_dir)
      system("gh codespace ssh -c #{codespace_name} -- 'test -d \"#{remote_dir}\"' 2>/dev/null")
    end

    def transfer_to_codespace(local_file, codespace_name, remote_file)
      # Use tar to preserve permissions and handle binary data
      cmd = "tar -cf - -C '#{File.dirname(local_file)}' '#{File.basename(local_file)}' | " \
            "gh codespace ssh -c #{codespace_name} -- 'tar -xf - -C \"#{File.dirname(remote_file)}\"'"
      system(cmd)
    end

    def transfer_from_codespace(remote_file, codespace_name, local_file)
      FileUtils.mkdir_p(File.dirname(local_file))
      cmd = "gh codespace ssh -c #{codespace_name} -- " \
            "'tar -cf - -C \"#{File.dirname(remote_file)}\" \"#{File.basename(remote_file)}\"' | " \
            "tar -xf - -C '#{File.dirname(local_file)}'"
      system(cmd)
    end

    def sync_directory_to_codespace(local_dir, codespace_name, remote_dir)
      ensure_remote_dir(codespace_name, File.dirname(remote_dir))
      cmd = "tar -cf - -C '#{File.dirname(local_dir)}' '#{File.basename(local_dir)}' | " \
            "gh codespace ssh -c #{codespace_name} -- 'tar -xf - -C \"#{File.dirname(remote_dir)}\"'"
      system(cmd)
    end

    def sync_directory_from_codespace(remote_dir, codespace_name, local_dir)
      FileUtils.mkdir_p(File.dirname(local_dir))
      cmd = "gh codespace ssh -c #{codespace_name} -- " \
            "'tar -cf - -C \"#{File.dirname(remote_dir)}\" \"#{File.basename(remote_dir)}\"' | " \
            "tar -xf - -C '#{File.dirname(local_dir)}'"
      system(cmd)
    end

    def find_remote_recent_sessions(codespace_name, remote_dir, days: DEFAULT_DAYS)
      # Find .jsonl files modified in last N days
      cmd = "gh codespace ssh -c #{codespace_name} -- " \
            "'find \"#{remote_dir}\" -maxdepth 1 -name \"*.jsonl\" -mtime -#{days} 2>/dev/null'"
      stdout, _stderr, status = Open3.capture3(cmd)
      return [] unless status.success?

      stdout.strip.split("\n").reject(&:empty?)
    end
  end
end
```

### Phase 2-4: Integration Updates

**bin/codespace-create** (add after line 173):
```ruby
# Sync Claude sessions to Codespace
puts "\n==> Syncing Claude sessions..."
begin
  require_relative '../lib/claude_session_syncer'
  repo_name = repository.split('/').last
  ClaudeSessionSyncer.sync_sessions_to_codespace(repo_name, codespace_name)
rescue LoadError, StandardError => e
  puts "    Warning: Could not sync sessions: #{e.message}"
end
```

**bin/codespace-ssh** (add in `sync_coding_agent_back` after line 75):
```ruby
# Sync Claude sessions from Codespace
puts "\n==> Syncing Claude sessions..."
begin
  require_relative '../lib/claude_session_syncer'
  ClaudeSessionSyncer.sync_sessions_from_codespace(repo_name, codespace_name)
rescue LoadError, StandardError => e
  puts "    Warning: Could not sync sessions: #{e.message}"
end
```

**bin/sync-to-codespace** (add session sync after provisioning loop)

### Phase 5: sync-dev-env Updates

Add `--sessions` and `--days` flags to support:
```bash
bin/sync-dev-env                        # Sync .coding-agent only (current behavior)
bin/sync-dev-env --sessions             # Sync both .coding-agent and sessions
bin/sync-dev-env --sessions-only        # Sync sessions only
bin/sync-dev-env --sessions --days 14   # Sync sessions from last 14 days
```

### Phase 6: Sync on Connect

Update `codespace-ssh` to do bidirectional sync before SSH:
```ruby
# In main, before system("gh codespace ssh ...")
if repo_matches
  puts "\n==> Syncing Claude sessions..."
  sync_sessions_bidirectional(codespace_name, repo_name)
end
```

### Phase 7: Background Sync Script and Launchd

**bin/sync-sessions-from-all-codespaces:**
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Syncs Claude sessions from all running Codespaces to local machine.
# Intended to be run periodically via launchd on work machines.

require 'json'
require 'open3'
require 'logger'

SCRIPT_DIR = File.expand_path('..', __dir__)
require_relative File.join(SCRIPT_DIR, 'lib', 'claude_session_syncer')

LOG_FILE = File.expand_path('~/Library/Logs/claude-session-sync.log')
FileUtils.mkdir_p(File.dirname(LOG_FILE))
LOGGER = Logger.new(LOG_FILE, 'weekly')
LOGGER.level = Logger::INFO

def main
  LOGGER.info("Starting scheduled session sync")

  # Get all available Codespaces
  stdout, stderr, status = Open3.capture3('gh codespace list --json name,repository,state')
  unless status.success?
    LOGGER.error("Failed to list Codespaces: #{stderr}")
    exit 1
  end

  codespaces = JSON.parse(stdout)
  available = codespaces.select { |cs| cs['state'] == 'Available' }

  if available.empty?
    LOGGER.info("No running Codespaces found")
    exit 0
  end

  LOGGER.info("Found #{available.length} running Codespace(s)")

  available.each do |cs|
    codespace_name = cs['name']
    repo_full_name = cs['repository']
    repo_name = repo_full_name&.split('/')&.last

    next unless repo_name

    LOGGER.info("Syncing sessions from #{codespace_name} (#{repo_name})")

    begin
      results = ClaudeSessionSyncer.sync_sessions_from_codespace(repo_name, codespace_name)
      LOGGER.info("  Pulled: #{results[:pulled]}, Skipped: #{results[:skipped]}")
    rescue StandardError => e
      LOGGER.error("  Failed: #{e.message}")
    end
  end

  LOGGER.info("Scheduled sync complete")
end

main
```

**roles/macos/templates/launchd/com.user.claude-session-sync.plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.claude-session-sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{ ansible_env.HOME }}/bin/sync-sessions-from-all-codespaces</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardOutPath</key>
    <string>{{ ansible_env.HOME }}/Library/Logs/claude-session-sync.log</string>
    <key>StandardErrorPath</key>
    <string>{{ ansible_env.HOME }}/Library/Logs/claude-session-sync.log</string>
    <key>RunAtLoad</key>
    <false/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
```

**Ansible task (work machines only):**
```yaml
- name: Install Claude session sync script
  copy:
    src: bin/sync-sessions-from-all-codespaces
    dest: "{{ ansible_env.HOME }}/bin/sync-sessions-from-all-codespaces"
    mode: '0755'
  when: ansible_facts["os_family"] == "Darwin"

- name: Install Claude session sync launchd plist (work machines only)
  template:
    src: launchd/com.user.claude-session-sync.plist
    dest: "{{ ansible_env.HOME }}/Library/LaunchAgents/com.user.claude-session-sync.plist"
    mode: '0644'
  when: ansible_facts["os_family"] == "Darwin" and bootstrap_use == 'work'
  notify: reload claude-session-sync

- name: Load Claude session sync launchd job
  command: launchctl load {{ ansible_env.HOME }}/Library/LaunchAgents/com.user.claude-session-sync.plist
  when: ansible_facts["os_family"] == "Darwin" and bootstrap_use == 'work'
  changed_when: false
  failed_when: false
```
