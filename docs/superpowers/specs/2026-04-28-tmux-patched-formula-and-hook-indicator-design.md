# Patched tmux 3.6a + hook-failure status indicator + upstream version guard

## Problem

Two related issues against tmux 3.6a on macOS:

1. **Real crash.** `window_copy_pipe_run` in tmux 3.6a dereferences a NULL `job` pointer at `+0x40` whenever `job_run` returns NULL. Triggered by `copy-pipe-and-cancel` (bound to `y`, `Y`, Enter in copy-mode-vi), which we use for `osc52-copy`. Confirmed by two `~/Library/Logs/DiagnosticReports/tmux-*.ips` reports with identical stacks. Upstream fix is commit [`2a5715f`](https://github.com/tmux/tmux/commit/2a5715f) — a one-line `if (job != NULL)` guard. The fix is on master only; no tagged release contains it as of 2026-04-28.
2. **Lost visibility into hook failures.** PR #120 silenced the visible flood of `'…tmux-sync-pane-border-status … returned 1'` warnings by routing hook stderr to `~/.local/state/tmux/hooks.log`. That stops the noise but means a genuine, recurring hook failure now goes unseen until somebody opens the log file.

## Goals

- Run a patched tmux 3.6a locally that contains the upstream NULL-deref fix, without depending on `--HEAD`.
- Make `bin/provision` fail loudly the moment upstream Homebrew tmux ships a release newer than 3.6a, so we know the workaround can be retired.
- Surface hook failures in the tmux status bar at the moment they happen, with enough information to decide whether to investigate, but without occupying space when there are none.

## Non-goals

- Linux dev host tmux. The crash hasn't been seen there. We'll revisit if it does.
- Auto-switching to upstream tmux when a newer release ships. The user wants explicit, manual handoff.
- Persisting failure state across tmux server restarts.

## Design

### 1. Patched Homebrew formula

New file: `roles/macos/files/homebrew/tmux-patched.rb`. A standard Homebrew formula tracking tmux 3.6a from the upstream release tarball, with a `patch do` block that applies commit `2a5715f` from GitHub. Declares `conflicts_with "tmux"` so vanilla and patched can't coexist. Header comment documents the rollback procedure.

Formula skeleton (final SHA values filled in at implementation time):

```ruby
class TmuxPatched < Formula
  desc "Terminal multiplexer (3.6a + window_copy_pipe_run NULL-deref fix from 2a5715f)"
  homepage "https://tmux.github.io/"
  url "https://github.com/tmux/tmux/releases/download/3.6a/tmux-3.6a.tar.gz"
  sha256 "<computed-at-impl>"
  license "ISC"

  depends_on "libevent"
  depends_on "ncurses"
  depends_on "utf8proc"

  conflicts_with "tmux", because: "Both install bin/tmux"

  patch do
    url "https://github.com/tmux/tmux/commit/2a5715fad5a3f7c7cec5ba8a0a26b85a0df2c259.patch"
    sha256 "<computed-at-impl>"
  end

  def install
    system "./configure", *std_configure_args,
           "--sysconfdir=#{etc}", "--enable-utf8proc"
    system "make", "install"
  end

  test do
    assert_match "tmux 3.6a", shell_output("#{bin}/tmux -V")
  end
end
```

### 2. Ansible install + version guard

In `roles/macos/tasks/main.yml`, near the existing tmux package install:

- **Detect & remove vanilla tmux** when present (`brew list --formula tmux`).
- **Install patched formula** via `brew install --formula {{ playbook_dir }}/roles/macos/files/homebrew/tmux-patched.rb`. Idempotency comes from a guard `when: '3.6a' not in brew_list_versions_tmux_patched.stdout`.
- **Upstream version guard**: query `brew info --json=v2 tmux`, parse `formulae[0].versions.stable`, fail with the rollback recipe if it isn't `3.6a`:

  ```yaml
  - name: Fail if upstream Homebrew tmux has moved past 3.6a
    ansible.builtin.fail:
      msg: |
        Upstream Homebrew tmux is now {{ upstream }}; the patched 3.6a workaround
        in this repo can be removed. Steps:
          1. brew uninstall --formula tmux-patched
          2. Delete roles/macos/files/homebrew/tmux-patched.rb
          3. Remove the tmux-patched install + version-guard tasks
          4. brew install tmux
          5. Commit
    vars:
      upstream: "{{ (tmux_upstream_info.stdout | from_json).formulae[0].versions.stable }}"
    when: upstream != "3.6a"
  ```

The guard runs after the install, so a healthy provision still completes when upstream is at 3.6a, and only fails when there's actually a new version to switch to.

### 3. Hook-failure status indicator

Replaces the inline `>/dev/null 2>>$HOME/.local/state/tmux/hooks.log || true` redirect from PR #120 with a dedicated wrapper script.

**Wrapper**: `roles/common/files/bin/tmux-hook-run` — small bash script (~25 lines) that:

- Runs the wrapped command with stdout discarded and stderr captured.
- On non-zero exit:
  - Appends a timestamped record to `~/.local/state/tmux/hooks.log` (full stderr, exit code, full argv).
  - Sets the tmux user option `@hook-last-error` to a status-bar-friendly string of the form `<script-basename>: <first-line-of-stderr>`, truncated to 60 characters.
- Always exits 0.

The wrapper's contract: never causes tmux to log a failed hook command, never spams the status bar at write time, and produces a single source-of-truth display string for the indicator.

**Status segment**: in `roles/macos/templates/dotfiles/tmux.conf` and `roles/linux/files/dotfiles/tmux.conf`:

```
set -g status-right '#{?@hook-last-error, #[bg=colour196#,fg=white#,bold] ! #{@hook-last-error} #[default],}'
set -g status-right-length 80
```

When `@hook-last-error` is empty/unset the format renders nothing — status-right occupies zero visual width. When set, a red badge appears on the right side showing the most recent failure.

If a new failure happens while a previous one is still displayed, the wrapper overwrites `@hook-last-error` and the bar updates to the latest. Earlier failures remain in the log file. This matches the user's "I just want to know something failed" intent — count is irrelevant; the most recent error message is what they investigate first.

**Dismiss / investigate**: bind `prefix + H`:

```
bind H display-popup -E -h 80% -w 80% "less +G ~/.local/state/tmux/hooks.log" \; set-option -gq @hook-last-error ""
```

`display-popup -E` runs `less +G` (start at end-of-file) and returns when the user quits less. The chained `set-option` clears the badge. Typical UX: see badge → `prefix + H` → read full log → `q` → badge gone.

**Hook lines**: each `run-shell -b` invocation in `pane-focus-in`, `client-session-changed`, `pane-title-changed` becomes:

```
run-shell -b "$HOME/.local/bin/tmux-hook-run <script> <args>"
```

No more inline `>/dev/null 2>>...` and no more `|| true` — the wrapper guarantees exit 0.

## Files

New:
- `roles/macos/files/homebrew/tmux-patched.rb`
- `roles/common/files/bin/tmux-hook-run`
- `roles/common/files/bin/tmux-hook-run.test`

Modified:
- `roles/macos/tasks/main.yml` — uninstall vanilla tmux, install patched formula, version-guard task
- `roles/common/tasks/main.yml` — install `tmux-hook-run` script
- `roles/macos/templates/dotfiles/tmux.conf` — wrapper-based hooks, status-right segment, `prefix+H` keybind
- `roles/linux/files/dotfiles/tmux.conf` — same as macos.conf for the wrapper/status/keybind pieces (skip the patched-formula bits; Linux still uses apt tmux)
- `roles/common/files/bin/tmux-window-bar-config.test` — assert wrapper invocation pattern, status-right segment, keybind, and forbid the old inline redirect form

## Test plan

**`tmux-hook-run.test`** (bash test, same style as the other repo tests):
- Wrapping a passing command: exit 0, log file unchanged, `@hook-last-error` left alone.
- Wrapping a failing command: exit 0 (always), log file gains a record containing exit code + stderr, `tmux set-option @hook-last-error` invoked with truncated message.
- Wrapping a missing command: same as failing — wrapper still exits 0.
- Truncation: stderr longer than 60 chars produces a 60-char-or-shorter `@hook-last-error` value.
- Tmux interactions are stubbed (PATH override) so the test runs without a tmux server.

**`tmux-window-bar-config.test`** additions:
- Both `tmux.conf` files contain `tmux-hook-run tmux-sync-pane-border-status #{pane_id}` (and analogous lines for the other scripts).
- Both contain the `#{?@hook-last-error,...,}` status segment and `set -g status-right-length 80`.
- Both contain the `bind H display-popup ... \; set-option -gq @hook-last-error` keybind.
- Both forbid the now-replaced inline redirect form (`2>>$HOME/.local/state/tmux/hooks.log`) — that pattern moves entirely into the wrapper.

**Integration**:
- `bin/provision --diff` runs clean.
- After provision, vanilla `tmux` is gone, `tmux-patched` is installed, `tmux -V` reports `3.6a`, and `tmux source-file ~/.tmux.conf` reloads with no warnings.
- Forcing a hook failure (e.g., `~/.local/bin/tmux-hook-run /bin/false`) populates `@hook-last-error`, the badge appears in the status bar, and `prefix + H` clears it.
- Editing the formula to claim upstream is at "3.7" (or by mocking the JSON output) makes the version-guard task fail with the rollback message.

## Rollback

When upstream Homebrew tmux ships a release containing the fix:

1. Provision fails on the version-guard task with the message above.
2. Run `brew uninstall --formula tmux-patched`.
3. Delete `roles/macos/files/homebrew/tmux-patched.rb`.
4. Remove the patched-tmux install task and the version-guard task from `roles/macos/tasks/main.yml`.
5. Re-add `tmux` to whatever vanilla install path existed before (or just `brew install tmux` once and let provision keep it idempotent).
6. Commit.

The hook-indicator and wrapper script stay regardless — they're independent of the tmux version.
