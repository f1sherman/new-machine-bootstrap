# Session Context Visibility

Improvements to quickly understand what's happening across Claude Code sessions — a catchup skill, tmux fixes, and statusline simplification.

## Summary

Four independent changes under a shared theme:

1. **`/catchup` skill** — on-demand session summary
2. **Tmux window name fix** — stop Claude Code version leaking into window names
3. **Tagged hostname in tmux status bar** — environment-aware host identification
4. **ccstatusline simplification** — strip to model + context percentage

---

## 1. `/catchup` Skill

### New File: `roles/common/files/config/skills/common/catchup/SKILL.md`

A prompt-only skill (no scripts or supporting files). When invoked, Claude scans its own conversation context — tasks, recent tool calls, plan state — and produces a 2-3 sentence summary covering:

1. What we're working on (the goal)
2. Where we left off (last completed step)
3. What's next (the immediate next action)

Frontmatter:

```yaml
---
name: catchup
description: >
  Use when the user wants a quick summary of the current session context.
  Use when switching between sessions, losing track, or needing a refresher
  on what's happening and what's next.
---
```

The skill body instructs Claude to be direct — no preamble, no filler, just the 2-3 sentence summary. It should reference tasks (if any exist), recent actions, and any active plan to derive the summary.

### Ansible Installation

Add a task to `roles/common/tasks/main.yml` to create the `catchup` skill directory and copy `SKILL.md`, following the same pattern as existing skills (e.g., `creating-handoffs`).

---

## 2. Tmux Window Name Fix

### Problem

Claude Code sends its version number (e.g., `2.1.92`) as an OSC terminal title escape sequence. With tmux's default `allow-rename on`, this overrides the window name, producing displays like `0:2.1.92*`.

### Fix

Add `set -g allow-rename off` to both tmux configs. This prevents programs from overriding window names via escape sequences. `automatic-rename` (already enabled) still works — it derives the window name from the running command, so windows show `claude`, `vim`, `zsh`, etc.

### Modified: `roles/macos/templates/dotfiles/tmux.conf`

Add after line 69 (`setw -g automatic-rename`):

```
set -g allow-rename off
```

### Modified: `roles/linux/files/dotfiles/tmux.conf`

Add after line 67 (`setw -g automatic-rename`):

```
set -g allow-rename off
```

---

## 3. Tagged Hostname in Tmux Status Bar

### Layout

Both platforms use the same ordering: branch, directory, then tagged hostname.

```
(branch) dirname [tag] hostname
```

Colors: branch in yellow, directory in cyan, tag+hostname in white (default fg).

### Tag Detection Logic

Evaluated in order (first match wins):

| Condition | Tag | Hostname source |
|---|---|---|
| `$CODESPACES` is set | `[cs]` | `$CODESPACE_NAME` |
| DevPod env var is set (verify: `$DEVPOD_NAME` or similar) | `[devpod]` | `hostname -s` |
| `$SSH_CONNECTION` is set | `[ssh]` | `hostname -s` |
| Otherwise | `[local]` | `hostname -s` |

### Implementation

The tag detection is too complex for an inline tmux format string. Create a small helper script.

### New File: `roles/common/files/bin/tmux-host-tag`

A shell script that outputs the tagged hostname string (e.g., `[local] brian-mbp`, `[cs] fluffy-robot-abc123`). Called from `status-left` in both tmux configs.

```bash
#!/usr/bin/env bash
if [ -n "$CODESPACES" ]; then
  echo "[cs] ${CODESPACE_NAME:-$(hostname -s)}"
elif [ -n "$DEVPOD_NAME" ]; then  # verify actual DevPod env var during implementation
  echo "[devpod] $(hostname -s)"
elif [ -n "$SSH_CONNECTION" ]; then
  echo "[ssh] $(hostname -s)"
else
  echo "[local] $(hostname -s)"
fi
```

### Modified: `roles/macos/templates/dotfiles/tmux.conf`

Replace the current `status-left` (line 55):

```
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#(tmux-host-tag)'
```

May need to increase `status-left-length` from 60 to 80 to accommodate the tagged hostname.

### Modified: `roles/linux/files/dotfiles/tmux.conf`

Replace the current `status-left` (line 53) with the same format as macOS:

```
set -g status-left '#[fg=yellow]#(branch=$(cd "#{pane_current_path}" && git branch --show-current 2>/dev/null); [ -n "$branch" ] && echo "($branch) ")#[fg=cyan]#{b:pane_current_path} #[fg=white]#(tmux-host-tag)'
```

The `status-left-length` is already 80 on Linux, which should be sufficient.

### Ansible Installation

Add a task to `roles/common/tasks/main.yml` to install `tmux-host-tag` to `~/.local/bin/`, following the same pattern as `tmux-session-name`.

### Session Switcher Unchanged

`tmux-switch-session` displays session names (set by `tmux-session-name`), not the status bar content. Since the tagged hostname is only in `status-left`, it does not appear in the session switcher. No changes needed to `tmux-switch-session`.

---

## 4. ccstatusline Simplification

### Current Display

```
Model: Opus 4.6 (1M context)  Ctx(u): 71.3%  Ctx: 45.9k  Block: 0hr 11m
```

### Proposed Display

```
opus[1m] ▶ 71.3%
```

Two components with a powerline separator: model name and usable context percentage.

### Modified: `roles/common/files/config/ccstatusline/settings.json`

Replace the current config with:

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
        "type": "context-percentage-usable",
        "color": "brightBlack",
        "metadata": {
          "inverse": "true"
        }
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
      "\ue0b1"
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

Changes from current:
- Removed `context-length` component (id 3)
- Removed `block-timer` component (id 5)
- Everything else (powerline, theme, flex mode) stays the same

---

## Success Criteria

1. `/catchup` produces a concise 2-3 sentence summary when invoked mid-session
2. Tmux windows show `claude`, `vim`, `zsh` etc. instead of version numbers like `2.1.92`
3. Tmux status bar shows `(branch) dirname [tag] hostname` with correct tags for local, codespace, SSH, and devpod environments
4. Tagged hostname does NOT appear in `tmux-switch-session` (M-8) — only session names
5. ccstatusline shows only model and context percentage with powerline separator
6. All changes provision cleanly via `bin/provision` on macOS
7. Linux tmux config gets the same `allow-rename off` and unified status-left format
