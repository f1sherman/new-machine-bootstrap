# Smart Upload Script Implementation Plan

## Overview

Create a Ruby script (`smart-upload`) with a tmux key binding (`M-u`) that intelligently handles file paths dragged into the terminal (or copied to clipboard):

1. **Not SSH'd** → Paste the local path as-is
2. **SSH'd to Codespace** → Upload via `gh codespace cp`, paste remote path
3. **SSH'd to regular server** → Upload via `scp`, paste remote path

**Note**: This script is **macOS-only**. It doesn't make sense in Codespaces since you're already remote - there's no local file to upload.

## Current State Analysis

### Existing Patterns
- `roles/common/files/bin/osc52-copy` - Ruby script for clipboard via OSC 52
- `roles/macos/templates/dotfiles/tmux.conf:20` - SSH detection: `ps -o args= -t '#{pane_tty}' | grep -qE '(^ssh |gh codespace ssh)'`
- `M-u` key binding is **not currently used** in either tmux config

### Key Discoveries
- tmux exposes `#{pane_tty}` for process inspection
- Codespace SSH: `gh codespace ssh -c <codespace-name>` (name from `-c` flag)
- Regular SSH: `ssh [options] [user@]hostname` (hostname is last non-option arg)
- `gh codespace cp` uses `remote:` prefix for remote paths
- `pbpaste` reads system clipboard - works with both drag-drop and Cmd+C

## Desired End State

After implementation:
1. User drags a file from Finder into Ghostty (path goes to clipboard) OR copies a file/path
2. User presses `M-u`
3. Script reads clipboard, detects SSH context, uploads if needed, pastes result

### Verification
- Local (no SSH): Path pasted unchanged
- Codespace SSH: File uploaded to `/tmp/uploads/`, remote path pasted
- Regular SSH: File uploaded to `/tmp/uploads/`, remote path pasted

## What We're NOT Doing

- Directory upload support (single files only for v1)
- Bidirectional sync (download from remote)
- trzsz integration (keeping it simple with scp/gh cp)
- Byte-level progress (just "Uploading..." and "Uploaded" messages)
- Codespaces deployment (not needed - script is for local macOS only)

## Implementation Approach

The script will:
1. Get the tmux pane TTY
2. Inspect processes on that TTY to detect SSH/Codespace
3. Read clipboard (via pbpaste on macOS)
4. If SSH'd, show "Uploading {filename}..." via `tmux display-message`
5. Upload the file (scp or gh codespace cp)
6. Show success/failure message via `tmux display-message` (replaces the uploading message)
7. Output the path (local or remote) for tmux to send to the pane

## Phase 1: Create the smart-upload Script

### Overview
Create the Ruby script that handles detection, upload, and path output.

### Changes Required

#### 1. New Script
**File**: `roles/macos/files/bin/smart-upload`

```ruby
#!/usr/bin/env ruby
#
# smart-upload: Upload dragged files to remote servers via tmux
#
# Usage: smart-upload <local-path> <pane-tty>
#
# Detects if the current tmux pane is SSH'd to a server and:
# - If not SSH'd: outputs the path unchanged
# - If SSH'd to Codespace: uploads via gh codespace cp, outputs remote path
# - If SSH'd to regular server: uploads via scp, outputs remote path

require 'fileutils'
require 'shellwords'

REMOTE_DIR = "/tmp/uploads"

def tmux_message(msg)
  system("tmux", "display-message", msg)
end

def find_ssh_process(pane_tty)
  return nil unless pane_tty && !pane_tty.empty?

  processes = `ps -o args= -t #{Shellwords.escape(pane_tty)} 2>/dev/null`.lines.map(&:strip)

  processes.each do |args|
    if args.match?(/\bgh codespace ssh\b/)
      return { type: :codespace, args: args }
    elsif args.match?(/^ssh\s/)
      return { type: :ssh, args: args }
    end
  end

  nil
end

def extract_codespace_name(args)
  if args =~ /-c\s+(\S+)/
    $1
  elsif args =~ /--codespace[=\s]+(\S+)/
    $1
  else
    # If no -c flag, gh uses interactive selection - we can't determine which one
    nil
  end
end

def extract_ssh_target(args)
  # Parse SSH args to find the target hostname
  # ssh [options] [user@]hostname [command]
  # Options that take arguments: -b, -c, -D, -E, -e, -F, -I, -i, -J, -L, -l, -m, -O, -o, -p, -Q, -R, -S, -W, -w

  parts = args.split
  parts.shift if parts.first == "ssh"

  skip_next = false
  opts_with_args = %w[-b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w]

  parts.each do |part|
    if skip_next
      skip_next = false
      next
    end

    if opts_with_args.include?(part)
      skip_next = true
      next
    end

    next if part.start_with?("-")

    # First non-option argument is the target
    return part
  end

  nil
end

def upload_to_codespace(local_path, codespace_name)
  filename = File.basename(local_path)
  remote_path = "#{REMOTE_DIR}/#{filename}"

  tmux_message("Uploading #{filename}...")

  # Create remote directory
  system("gh", "codespace", "ssh", "-c", codespace_name, "--", "mkdir", "-p", REMOTE_DIR,
         out: File::NULL, err: File::NULL)

  # Upload file
  success = system("gh", "codespace", "cp", "-c", codespace_name,
                   local_path, "remote:#{remote_path}",
                   out: File::NULL, err: File::NULL)

  if success
    tmux_message("Uploaded to #{remote_path}")
    remote_path
  else
    tmux_message("Upload failed!")
    nil
  end
end

def upload_to_ssh(local_path, target)
  filename = File.basename(local_path)
  remote_path = "#{REMOTE_DIR}/#{filename}"

  tmux_message("Uploading #{filename}...")

  # Create remote directory and upload
  system("ssh", target, "mkdir", "-p", REMOTE_DIR,
         out: File::NULL, err: File::NULL)

  success = system("scp", "-q", local_path, "#{target}:#{remote_path}",
                   out: File::NULL, err: File::NULL)

  if success
    tmux_message("Uploaded to #{remote_path}")
    remote_path
  else
    tmux_message("Upload failed!")
    nil
  end
end

def main
  if ARGV.length < 2
    warn "Usage: smart-upload <local-path> <pane-tty>"
    exit 1
  end

  local_path = ARGV[0].strip.gsub(/\A['"]|['"]\z/, '') # Remove quotes if present
  pane_tty = ARGV[1]

  unless File.exist?(local_path)
    # Not a valid local file - just output as-is (might be pasting something else)
    print local_path
    exit 0
  end

  ssh_info = find_ssh_process(pane_tty)

  if ssh_info.nil?
    # Not SSH'd - output local path
    print local_path
    exit 0
  end

  case ssh_info[:type]
  when :codespace
    codespace = extract_codespace_name(ssh_info[:args])
    if codespace.nil?
      warn "Could not determine codespace name"
      print local_path
      exit 1
    end

    remote_path = upload_to_codespace(local_path, codespace)
    if remote_path
      print remote_path
    else
      warn "Upload to codespace failed"
      print local_path
      exit 1
    end

  when :ssh
    target = extract_ssh_target(ssh_info[:args])
    if target.nil?
      warn "Could not determine SSH target"
      print local_path
      exit 1
    end

    remote_path = upload_to_ssh(local_path, target)
    if remote_path
      print remote_path
    else
      warn "Upload via scp failed"
      print local_path
      exit 1
    end
  end
end

main
```

### Success Criteria

#### Automated Verification
- [x] Script is executable: `test -x roles/macos/files/bin/smart-upload`
- [x] Ruby syntax is valid: `ruby -c roles/macos/files/bin/smart-upload`
- [x] Script handles missing args gracefully: `roles/macos/files/bin/smart-upload 2>&1 | grep -q "Usage"`

#### Manual Verification
- [x] Test locally (no SSH): `smart-upload /tmp/test.txt ""` outputs `/tmp/test.txt`
- [x] Test with mock SSH process detection

---

## Phase 2: Add Ansible Deployment Task

### Overview
Ensure the script is deployed to `~/bin/` on macOS.

### Changes Required

#### 1. Add macOS bin/ Scripts Task
**File**: `roles/macos/tasks/main.yml`

Add a task to copy scripts from `roles/macos/files/bin/` to `~/bin/`:

```yaml
- name: Install macOS-specific scripts
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "{{ ansible_facts['user_dir'] }}/bin/"
    mode: '0755'
  with_fileglob:
    - "bin/*"
```

This follows the same pattern as the common role but for macOS-specific scripts.

### Success Criteria

#### Automated Verification
- [ ] After provisioning: `test -x ~/bin/smart-upload`
  - (Task added to Ansible playbook - requires running `bin/provision` to verify)

---

## Phase 3: Add tmux Key Binding

### Overview
Add `M-u` binding to macOS tmux config that reads clipboard, runs smart-upload, and sends result to pane.

### Changes Required

#### 1. macOS tmux.conf
**File**: `roles/macos/templates/dotfiles/tmux.conf`

Add after line 24 (after the `M-y` binding):

```tmux
# Smart upload: reads clipboard path, uploads if SSH'd, pastes result
bind-key -n M-u run-shell -b "tmux set-buffer \"$(pbpaste)\" && \
  result=$({{ ansible_facts['user_dir'] }}/bin/smart-upload \"$(tmux show-buffer)\" \"#{pane_tty}\") && \
  tmux send-keys \"$result\""
```

### Success Criteria

#### Automated Verification
- [x] macOS config contains M-u: `grep -q "M-u" roles/macos/templates/dotfiles/tmux.conf`

#### Manual Verification
- [x] After tmux source-file: `M-u` binding works
- [x] Drag file into Ghostty, press `M-u`, path appears
- [x] When SSH'd to Codespace: file uploads, remote path appears
- [ ] When SSH'd to regular server: file uploads, remote path appears

## Testing Strategy

### Unit Tests
- Script correctly identifies no SSH (empty pane_tty)
- Script correctly parses `ssh user@host`
- Script correctly parses `ssh -p 22 host`
- Script correctly parses `gh codespace ssh -c name`
- Script handles non-existent files gracefully

### Integration Tests
- Local test: drag file, M-u, local path appears
- Codespace test: SSH to Codespace, drag file, M-u, upload succeeds, remote path appears
- Regular SSH test: SSH to server, drag file, M-u, upload succeeds, remote path appears

### Manual Testing Steps
1. Open Ghostty with tmux
2. Copy a file path (Cmd+C on a file in Finder, or copy path text)
3. Press `M-u` - local path should appear (confirms local passthrough)
4. SSH to a Codespace: `gh codespace ssh -c <name>`
5. Copy a local file path
6. Press `M-u` - should upload and paste `/tmp/uploads/<filename>`
7. Verify: `ls /tmp/uploads/` shows the file
8. Repeat with regular SSH server

## Performance Considerations

- Script runs synchronously; large files will block briefly during upload
- Consider adding `run-shell -b` (background) if blocking becomes an issue, but then error handling is harder

## References

- [gh codespace cp documentation](https://cli.github.com/manual/gh_codespace_cp)
- Existing SSH detection pattern: `roles/macos/templates/dotfiles/tmux.conf:20`
- Existing script patterns: `roles/common/files/bin/osc52-copy`

## Summary of Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `roles/macos/files/bin/smart-upload` | Create | Ruby script for smart upload |
| `roles/macos/tasks/main.yml` | Modify | Add task to deploy macOS-specific scripts |
| `roles/macos/templates/dotfiles/tmux.conf` | Modify | Add `M-u` key binding |
