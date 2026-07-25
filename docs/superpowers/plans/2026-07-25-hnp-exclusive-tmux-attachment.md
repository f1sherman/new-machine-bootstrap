# HNP Exclusive Tmux Attachment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make plain `hnp` reconnect only to a detached canonical tmux session and create a distinct session whenever the canonical session already has a client.

**Architecture:** Replace tmux `new-session -A` with an explicit, file-locked session decision. The launcher creates or selects a target, starts its tmux client while holding the lock, and releases the lock only after tmux reports the target attached, closing the concurrent check/attach race.

**Tech Stack:** Ruby standard library (`File#flock`, `Process.spawn`, `Process.wait2`, `Open3`, Minitest), tmux CLI, Ansible-managed executable files.

## Global Constraints

- NMB `roles/common/files/bin/hnp` is the source of truth for the affected launcher.
- Reconnect to exact session `=hnp` only when `session_attached == 0`.
- Create a unique `hnp-<pid>-<timestamp>` session when canonical `hnp` is already attached.
- Prevent concurrent launchers from claiming the same detached session.
- Preserve SSH routing, HNP checkout selection, `OPENAI_API_KEY` removal, Pi argument forwarding, and direct Pi execution inside tmux.
- Add no external dependency; locking and process control must use Ruby's standard library.

---

## File Structure

- `roles/common/files/bin/hnp`: owns host routing, tmux session selection, serialized attachment handoff, and Pi execution.
- `tests/hnp.rb`: isolated behavioral harness with fake `ssh`, `pi`, and stateful `tmux` executables; proves launcher behavior rather than source literals.

### Task 1: Serialize HNP tmux selection and attachment

**Files:**
- Modify: `roles/common/files/bin/hnp`
- Create: `tests/hnp.rb`

**Interfaces:**
- Consumes: environment variables `HOME`, `PATH`, `HNP_DEV_HOST`, `HNP_TMUX_SESSION`, `HNP_HOSTNAME`, `HNP_REMOTE`, `SSH_CONNECTION`, `TMUX`, and optional `HNP_TMUX_LOCK_FILE` / `HNP_TMUX_ATTACH_TIMEOUT` test and operational overrides.
- Produces: `attach_or_create_tmux_session(session_name, repo_path, command)` behavior that exits with the tmux client's status after confirming attachment; exact canonical target selection through tmux formats.

- [ ] **Step 1: Add a failing behavioral test for detached versus attached canonical sessions**

Create `tests/hnp.rb` with Minitest setup that copies launcher execution into a temporary `HOME`, creates `$HOME/projects/home-network-provisioning`, prepends a fake-bin directory to `PATH`, and stores fake tmux state in JSON protected by `flock`.

The state format must be:

```ruby
{
  "sessions" => [
    { "name" => "hnp", "attached" => 0, "command" => "pi" }
  ],
  "attachments" => [],
  "created" => []
}
```

The fake tmux must implement these real command boundaries:

```ruby
case ARGV.shift
when "has-session"
  # Exact-match ARGV target after deleting a leading '='; exit 0/1.
when "display-message"
  # Print session_attached for format '#{session_attached}'.
when "new-session"
  # Record -s name and trailing shell command; create detached session.
when "attach-session"
  # Increment attached under JSON lock, record target, optionally sleep,
  # then decrement attached before exiting so capture3 completes.
else
  abort "unexpected tmux command"
end
```

Add these assertions:

```ruby
def test_detached_canonical_session_is_reconnected
  set_sessions([{ "name" => "hnp", "attached" => 0, "command" => "pi" }])
  _out, err, status = run_hnp

  assert status.success?, err
  assert_equal ["hnp"], state.fetch("attachments")
  assert_equal [], state.fetch("created")
end

def test_attached_canonical_session_creates_unique_session
  set_sessions([{ "name" => "hnp", "attached" => 1, "command" => "pi" }])
  _out, err, status = run_hnp

  assert status.success?, err
  assert_match(/\Ahnp-\d+-\d+\z/, state.fetch("created").sole.fetch("name"))
  assert_equal state.fetch("created").sole.fetch("name"), state.fetch("attachments").sole
  assert_equal 1, session("hnp").fetch("attached")
end
```

Use ordinary array indexing instead of framework-specific `sole` if the installed Ruby lacks it.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
ruby tests/hnp.rb
```

Expected: the detached test may pass through existing `-A`, but the attached test fails because the attachment record is `hnp` and no unique session was created.

- [ ] **Step 3: Add the failing concurrent-launch test**

Configure fake `attach-session` to hold `attached == 1` for `FAKE_TMUX_ATTACH_DELAY=0.25`. Start two launcher subprocesses simultaneously against one detached canonical session:

```ruby
def test_concurrent_launchers_do_not_share_detached_canonical_session
  set_sessions([{ "name" => "hnp", "attached" => 0, "command" => "pi" }])
  env = launcher_env("FAKE_TMUX_ATTACH_DELAY" => "0.25")

  results = 2.times.map { Thread.new { Open3.capture3(env, HNP) } }.map(&:value)
  attachments = state.fetch("attachments")

  results.each { |_out, err, status| assert status.success?, err }
  assert_equal 2, attachments.length
  assert_equal 2, attachments.uniq.length,
    "concurrent launchers attached the same session: #{attachments.inspect}"
  assert_includes attachments, "hnp"
end
```

- [ ] **Step 4: Run the focused test and confirm the concurrency RED failure**

Run:

```bash
ruby tests/hnp.rb
```

Expected: FAIL because both existing `tmux new-session -A -s hnp` invocations attach to `hnp`.

- [ ] **Step 5: Implement the locked attachment handoff**

In `roles/common/files/bin/hnp`, add constants and helpers shaped as follows:

```ruby
TMUX_ATTACH_TIMEOUT = Float(ENV.fetch("HNP_TMUX_ATTACH_TIMEOUT", "2"))
TMUX_LOCK_FILE = ENV.fetch(
  "HNP_TMUX_LOCK_FILE",
  File.join(ENV.fetch("TMPDIR", "/tmp"), "hnp-tmux-#{Process.uid}.lock")
)

def tmux_session_attached(session_name)
  output = IO.popen(
    ["tmux", "display-message", "-p", "-t", "=#{session_name}:", '#{session_attached}'],
    err: File::NULL,
    &:read
  )
  return nil unless $CHILD_STATUS.success?

  Integer(output.strip, exception: false)
end

def create_tmux_session(session_name, repo_path, command)
  system(
    "tmux", "new-session", "-d", "-s", session_name,
    "-c", repo_path, command.shelljoin
  ) || abort("failed to create hnp tmux session #{session_name}")
end
```

Require `English` for `$CHILD_STATUS`. Select the target under `File.open(TMUX_LOCK_FILE, File::RDWR | File::CREAT, 0o600)` plus `flock(File::LOCK_EX)`:

```ruby
attached = tmux_session_attached(TMUX_SESSION)
selected = if attached.nil?
  create_tmux_session(TMUX_SESSION, repo_path, pi_command)
  TMUX_SESSION
elsif attached.zero?
  TMUX_SESSION
else
  unique = "#{TMUX_SESSION}-#{Process.pid}-#{Time.now.to_i}"
  create_tmux_session(unique, repo_path, pi_command)
  unique
end
```

Spawn the client while the lock remains held:

```ruby
client_pid = Process.spawn("tmux", "attach-session", "-t", "=#{selected}")
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TMUX_ATTACH_TIMEOUT
loop do
  break if tmux_session_attached(selected).to_i.positive?

  exited = Process.waitpid(client_pid, Process::WNOHANG)
  abort "failed to attach hnp tmux session #{selected}" if exited
  abort "timed out attaching hnp tmux session #{selected}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  sleep 0.01
end
lock.flock(File::LOCK_UN)
_, status = Process.wait2(client_pid)
exit(status.exitstatus || 1)
```

Place lock release in `ensure` so errors and interrupts do not retain it. Avoid `-A`. Preserve the existing non-tmux local path and inside-tmux path unchanged.

- [ ] **Step 6: Run the focused test and confirm GREEN**

Run:

```bash
ruby tests/hnp.rb
```

Expected: all detached, attached, and concurrent cases pass with zero failures.

- [ ] **Step 7: Add regression coverage for routing and argument preservation**

Extend `tests/hnp.rb` with:

```ruby
def test_inside_tmux_runs_pi_directly_with_arguments
  _out, err, status = run_hnp("two words", "$(bad)", "TMUX" => "/tmp/tmux", "PI_CAPTURE" => @pi_capture)

  assert status.success?, err
  assert_equal [repo_path, "two words", "$(bad)"], File.readlines(@pi_capture, chomp: true)
  assert_equal [], state.fetch("attachments")
end

def test_remote_host_routes_to_dev_with_shell_escaped_arguments
  _out, err, status = run_hnp(
    "two words", "$(bad)",
    "HNP_HOSTNAME" => "laptop", "FAKE_SSH_AVAILABLE" => "1", "SSH_CAPTURE" => @ssh_capture
  )

  assert status.success?, err
  args = File.readlines(@ssh_capture, chomp: true)
  assert_equal "-t", args.fetch(0)
  assert_equal "dev", args.fetch(1)
  assert_includes args.fetch(2), "HNP_REMOTE=1"
  assert_includes args.fetch(2), "two\\ words"
  assert_includes args.fetch(2), "\\\$\\\(bad\\\)"
end
```

The fake Pi records `pwd` followed by each argument. The fake SSH exits according to `FAKE_SSH_AVAILABLE` for the probe and records the final invocation for the routing assertion.

- [ ] **Step 8: Run focused and syntax verification**

Run:

```bash
ruby tests/hnp.rb
ruby -c roles/common/files/bin/hnp
git diff --check
```

Expected: all tests pass, `Syntax OK`, and `git diff --check` emits no output.

- [ ] **Step 9: Commit implementation and behavior coverage**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Prevent duplicate HNP tmux attachments" \
  roles/common/files/bin/hnp tests/hnp.rb
```

- [ ] **Step 10: Run repository verification**

Run the focused test again plus the tmux startup suite most closely related to session attachment locking:

```bash
ruby tests/hnp.rb
ruby tests/tmux-restore-startup.rb
```

Expected: both suites pass with zero failures and zero errors.

- [ ] **Step 11: Provision from the feature worktree and verify deployed behavior**

Run:

```bash
bin/provision
```

Then confirm the installed file matches the worktree source and run a controlled tmux proof on `dev`: create an attached canonical `hnp` session with a harmless sleeper command, invoke the deployed launcher's tmux selection through the focused harness or a disposable overridden `HNP_TMUX_SESSION`, and verify tmux lists two distinct sessions rather than two clients on one session. Clean up all disposable sessions afterward.

Expected: provisioning succeeds; installed launcher checksum equals `roles/common/files/bin/hnp`; attached canonical session retains one client; second launch uses a unique HNP session.
