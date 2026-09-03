# Smart Upload Explicit Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit, quiet SSH-target mode to `smart-upload` without changing tmux behavior.

**Architecture:** Parse additive options in the existing Ruby executable. Reuse its SSH transfer path and isolate status output behind a small reporter so Herdr callers can suppress tmux calls.

**Tech Stack:** Ruby, OptionParser, Minitest, Open3

**Spec:** `docs/superpowers/specs/2026-09-02-smart-upload-explicit-target-design.md`

## Global Constraints

- Existing two-positional-argument tmux calls must behave unchanged.
- `--ssh-target TARGET` must bypass pane process detection and pass TARGET as one argv value.
- `--quiet-status` must suppress all tmux status commands.
- Do not add Herdr or inventory-specific behavior.

---

### Task 1: Explicit smart-upload target

**Files:**
- Modify: `roles/macos/files/bin/smart-upload`
- Create: `tests/smart-upload.rb`

**Interfaces:**
- Consumes: `smart-upload [options] <local-path-or-empty> <pane-tty>`
- Produces: `--ssh-target TARGET` and `--quiet-status`

- [ ] **Step 1: Write the failing behavioral tests**

Create a Minitest test that runs the production executable in a temporary HOME
and PATH. Fake `ssh`, `scp`, and `tmux` executables write their argv to log files.
Use a real temporary source file. Assert that:

```ruby
stdout, stderr, status = Open3.capture3(
  env,
  SCRIPT,
  "--ssh-target", "dev-alias",
  "--quiet-status",
  source_path,
  ""
)
assert status.success?, stderr
assert_equal "/tmp/uploads/example.txt", stdout
assert_equal ["dev-alias", "mkdir", "--parents", "/tmp/uploads"],
             File.readlines(ssh_log, chomp: true)
assert_equal ["-q", source_path, "dev-alias:/tmp/uploads/example.txt"],
             File.readlines(scp_log, chomp: true)
refute File.exist?(tmux_log)
```

Add a second invocation with `--ssh-target ""` and assert nonzero status and no
SSH or SCP call.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `ruby tests/smart-upload.rb`

Expected: FAIL because `smart-upload` treats the options as positional input and
does not use the explicit target.

- [ ] **Step 3: Implement the minimal option behavior**

Use `OptionParser` to parse both options. Reject an empty explicit target. Move
tmux messaging behind a reporter with a `quiet` flag:

```ruby
module Status
  class << self
    attr_accessor :quiet

    def message(text, duration: nil)
      return if quiet

      args = ["tmux", "display-message"]
      args += ["-d", duration.to_s] if duration
      system(*args, text)
    end
  end
end
```

After local clipboard resolution, select the existing upload path explicitly:

```ruby
if options[:ssh_target]
  remote_path = upload_to_ssh(local_path, options[:ssh_target])
  if remote_path
    print remote_path
    exit 0
  end
  warn "Upload via scp failed"
  print local_path
  exit 1
end
```

Leave all existing automatic process detection below that branch.

- [ ] **Step 4: Run focused and syntax verification**

Run:

```bash
ruby tests/smart-upload.rb
ruby -c roles/macos/files/bin/smart-upload
```

Expected: all tests pass and syntax is `Syntax OK`.

- [ ] **Step 5: Run repository verification and commit**

Run the repository's available Ruby and provisioning validation commands, then
commit `roles/macos/files/bin/smart-upload` and `tests/smart-upload.rb` with an
imperative message.
