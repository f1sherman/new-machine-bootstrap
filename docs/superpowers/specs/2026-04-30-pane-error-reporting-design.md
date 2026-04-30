# Pane-level error reporting primitive

## Problem

The 2026-04-28 spec (tmux 3.6a + hook indicator) introduced `tmux-hook-run`, a single-purpose wrapper that surfaces tmux hook failures via the server-global `@hook-last-error` option and logs them to `~/.local/state/tmux/hooks.log`. The status-right segment renders a red `!` badge with the most recent message, and `prefix + h` opens the log and clears the badge.

That worked for tmux hooks, but several other classes of script have the same "silent failure" shape and currently no place to report:

- Long-running pollers and watchers that run inside Claude Code's `Monitor` tool. They iterate every 60s, can fail transiently (network, rate limit, malformed output from a subprocess), and currently swallow stderr — a fail-open default downstream produces wrong output that only surfaces as a downstream symptom.
- Background helpers spawned from tmux key bindings (review-toggle, smart-upload, etc.) that catch their own errors and continue.
- Any user-launched script that the user wants to know failed without watching a terminal.

Two specific gaps:

1. **No reusable primitive.** `tmux-hook-run` is a *wrap-and-run* convenience, not a *report-failure* primitive. Scripts that detect a failure mid-run (e.g., a subprocess returned successful exit but malformed JSON) can't easily plug in.
2. **Server-global is too coarse.** `@hook-last-error` is set with `-g`, so the most recent failure overwrites whichever pane caused it. With multiple pollers running in different panes, you can't tell which pane is sick. A pane-scoped indicator would attach the badge to the work that produced it.

## Goals

- Provide a reusable shell primitive any script can call to report a failure: `report-pane-error <name> <message>`. One line in the caller.
- Show the indicator per-pane, not server-globally. Each pane gets its own `@pane-last-error` user option; multiple simultaneous failures across panes are independently visible.
- Keep the existing UX shape: red `!` badge, `prefix + h` opens log and dismisses, log file inspectable as plain text.
- Migrate `tmux-hook-run` to use the new primitive without changing its caller-facing behavior.
- Work cleanly when invoked outside a tmux pane (no badge, log only) so non-tmux contexts (cron, ssh-with-no-tmux) degrade gracefully.

## Non-goals

- Cross-tmux propagation (inner tmux in a remote dev host → outer tmux on the laptop). The inner tmux renders its own status bar inside the outer pane, so the badge is visible from the laptop *while looking at that pane*. No DCS passthrough plumbing.
- Aggregating failures into a count or history view. Most-recent-message-wins matches the existing UX.
- Persisting badges across tmux server restarts.
- Notifications outside tmux (system notifications, terminal bells). Out of scope; can layer on later if needed.

## Design

### 1. The primitive: `report-pane-error`

New file: `roles/common/files/bin/report-pane-error`. Bash, ~30 lines. Always exits 0.

**Contract:**

```
report-pane-error <name> <message> [--pane <pane_id>]
report-pane-error <name>           [--pane <pane_id>] < message_on_stdin
```

`<name>` is a short identifier for the source (e.g., script basename). `<message>` is a one-line human-readable description of the failure; multi-line stderr can be piped on stdin and the first line is used for the badge text while the full content goes to the log.

**Pane id resolution order:**

1. `--pane <pane_id>` flag if present.
2. `$TMUX_PANE` environment variable (tmux sets this for shells running inside a pane, and child processes inherit it).
3. None — skip the badge step, still write the log entry.

**Behavior on every call:**

1. Append a timestamped record to `~/.local/state/failures.log`:
   ```
   [2026-04-30T12:34:56-0500] pane=%2 name=<source>
   message: <one-line summary>
   <full stdin content if any>
   ---
   ```
2. If a pane id was resolved: `tmux set-option -pq -t "$pane_id" @pane-last-error "<name>: <truncated-msg>"` (60-char truncation as today). Errors from the `tmux` invocation are swallowed (`|| true`) so a missing tmux server never breaks the caller.
3. Exit 0.

The log directory `~/.local/state/` is created on first call (`mkdir -p`) so the script is self-bootstrapping.

### 2. Status display

**Per-pane sigil in the pane border** — every pane shows a glanceable `!` when its `@pane-last-error` is set:

```
set -g pane-border-format '#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} #(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}" "#{pane_id}")#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} '
```

When the option is empty/unset the conditional renders nothing — pane border occupies the same width as today.

**Full message in status-right for the active pane:**

```
set -g status-right '#{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #{@pane-last-error} #[default],}'
```

`#{@pane-last-error}` in a format string resolves with the active pane's value first, falling back through window/session/server scope. So the active pane's message shows in status-right; inactive panes show only the `!` sigil in their border. Switching panes updates status-right.

### 3. Dismiss / investigate

The existing `prefix + h` binding stays, with two changes — the log path and the option scope:

```
bind h display-popup -E -h 80% -w 80% "less +G ~/.local/state/failures.log" \; set-option -pqu @pane-last-error
```

`-pqu` clears the per-pane option on the *active* pane. Multiple flagged panes → press `prefix + h` from each one to clear that one. (Alternative: `-gqu` to clear globally; rejected because it loses information about other angry panes the user hasn't visited yet.)

### 4. `tmux-hook-run` migration

The wrapper keeps its current signature and exit-0 contract. Internally it stops setting `@hook-last-error` directly and instead calls:

```bash
"$HOME/.local/bin/report-pane-error" "${1##*/}" "$err" --pane "${TMUX_HOOK_PANE_ID:-}"
```

To pass a pane id through, the hook lines in `tmux.conf` get an explicit env var:

```
set-hook -g pane-focus-in 'run-shell -b "TMUX_HOOK_PANE_ID=#{pane_id} $HOME/.local/bin/tmux-hook-run tmux-remote-title publish"; ...'
```

Hooks that already pass `#{pane_id}` as a positional arg keep doing so for the wrapped command's own use; the env var is the explicit channel for the *wrapper* to know which pane to flag.

When `TMUX_HOOK_PANE_ID` is unset (e.g., a hook fires before any pane exists), the wrapper degrades to log-only — same as any non-tmux caller of `report-pane-error`.

### 5. Migration of state

- **Log path:** `~/.local/state/tmux/hooks.log` → `~/.local/state/failures.log`. The Ansible task that creates the directory is updated. No copy of old log content; users who care can `cat` it manually before the cutover.
- **Option name:** `@hook-last-error` → `@pane-last-error`, scope `-g` → `-p`. Old global value is harmless but stale; the spec includes a one-line cleanup `tmux set-option -gqu @hook-last-error 2>/dev/null || true` in the same provision step that installs the new tmux.conf, so the first reload removes the orphan global.
- **Status segments:** every reference to `@hook-last-error` in both tmux.conf templates is replaced. Tests assert the old name no longer appears.

## Files

New:

- `roles/common/files/bin/report-pane-error`
- `roles/common/files/bin/report-pane-error.test`

Modified:

- `roles/common/files/bin/tmux-hook-run` — delegates to `report-pane-error`; preserves wrap-and-run UX.
- `roles/common/files/bin/tmux-hook-run.test` — assert wrapper now invokes `report-pane-error` (stub it on PATH); failure paths still produce log records and badge calls; passing commands still no-op.
- `roles/common/tasks/main.yml` — install `report-pane-error` script alongside `tmux-hook-run`; ensure `~/.local/state/` exists.
- `roles/macos/templates/dotfiles/tmux.conf` — replace status-right segment, replace `prefix+h` keybind, add the per-pane sigil to `pane-border-format`, add `TMUX_HOOK_PANE_ID=#{pane_id}` to each `tmux-hook-run` invocation, drop the comment block referencing `@hook-last-error`.
- `roles/linux/files/dotfiles/tmux.conf` — same edits as macOS.
- `roles/common/files/bin/tmux-window-bar-config.test` — assert new format strings, new keybind path, forbid old `@hook-last-error` references and old `~/.local/state/tmux/hooks.log` path.

## Test plan

**`report-pane-error.test`:**

- With `--pane`: log file gains a record (timestamp, pane id, name, message); `tmux set-option -p` is invoked with the right pane id and a 60-char-or-shorter value (verify via stub `tmux` on PATH).
- With `$TMUX_PANE` env: same as `--pane`, pane id sourced from env.
- Without any pane info: log file gains a record; no `tmux set-option` invocation; exit 0.
- Stdin path: piped multi-line message logs in full, badge text is the first line.
- Long message: stored full in log, truncated for the option to ≤60 chars.
- `tmux` binary missing: still exits 0, log entry still written.

**`tmux-hook-run.test` (updated):**

- Passing wrapped command: exit 0, log unchanged, no `report-pane-error` call.
- Failing wrapped command: exit 0, `report-pane-error` invoked once with `<basename>` + first line of stderr + `--pane "$TMUX_HOOK_PANE_ID"`.
- `TMUX_HOOK_PANE_ID` unset: `report-pane-error` invoked without `--pane` (or with empty value), wrapper still exits 0.
- Backward shape: same exit code (0), same stdin/stdout/stderr handling, same argv pass-through to the wrapped command.

**`tmux-window-bar-config.test` additions:**

- Both tmux.conf files contain `#{?#{@pane-last-error}, ! ,}` (or equivalent) in `pane-border-format`.
- Both contain `set -g status-right '#{?#{@pane-last-error}, ... ,}'`.
- Both contain `bind h display-popup ... ~/.local/state/failures.log ... \; set-option -pqu @pane-last-error`.
- Both contain `TMUX_HOOK_PANE_ID=#{pane_id}` on each `tmux-hook-run` invocation.
- Both forbid: `@hook-last-error`, `~/.local/state/tmux/hooks.log`, `set-option -gq @hook-last-error`.

**Integration:**

- `bin/provision --diff` clean.
- After provision, `tmux source-file ~/.tmux.conf` reloads with no warnings.
- `~/.local/bin/report-pane-error test "synthetic failure"` from inside a pane: badge appears on that pane only; `prefix + h` opens the log (showing the entry) and clears the badge.
- Same call from a second pane: that pane lights up too without affecting the first.
- `~/.local/bin/tmux-hook-run /bin/false`: badge appears on calling pane.
- `unset TMUX_PANE; ~/.local/bin/report-pane-error test "no pane"`: log entry written, no badge anywhere, exit 0.

## Rollback

If the per-pane scheme proves unworkable in practice:

1. Revert the tmux.conf changes (status-right, pane-border-format, keybind, hook env var).
2. Restore the prior `tmux-hook-run` body (set `@hook-last-error` directly).
3. Move `~/.local/state/failures.log` back to `~/.local/state/tmux/hooks.log` (or just keep the new path; a one-line `bind h` rewrite is the only thing that depended on it).
4. `report-pane-error` and its test can stay — they're independently useful and harmless if no caller invokes them.

The primitive is additive; the migration of `tmux-hook-run` and the tmux.conf segments are the only revertable surface.
