# tmux Pane Link Design

## Problem

After `repo-start` claims a pane, the pane border surfaces a `branch | host`
label. Once a pull request exists for that branch, there is no way to surface
it in the tmux UI. Pasting the URL into the status would be visually noisy and
not callable from helpers in other repos.

The goal: a tiny, repo-local primitive that other repos and skills can call to
attach a clickable identifier (e.g. `GH#1234`) to the current pane. In Ghostty,
holding command and clicking the identifier opens the URL in the browser.

## Goals

- New script `tmux-pane-link` that any caller can invoke as
  `tmux-pane-link LABEL URL` to attach a clickable annotation to the current
  pane, or `tmux-pane-link --clear` to remove it.
- Clickability via OSC 8. tmux 3.4+ embeds OSC 8 in style strings, and Ghostty
  honors them on cmd+click — both already work without configuration.
- Render the annotation in `pane-border-format` next to the existing repo
  label, so it composes with `repo-start` rather than replacing it.
- Auto-clear the annotation when the pane's repo context goes away
  (`tmux-agent-worktree clear`, called by `repo-end`).
- Reject non-`http(s)` URLs and any payload that could smuggle terminal
  control sequences.

## Non-Goals

- Multi-slot annotations. v1 is single slot, last writer wins. If two callers
  set a link on the same pane, the second overwrites the first.
- Auto-discovery of PRs. The script does not call `gh`. Callers know what
  link they want to attach.
- Cross-pane state. Each pane has its own `@pane-link` user option.
- Persisting across tmux server restart. tmux-resurrect is not extended.
- Surfacing the annotation in the global status bar. Pane border only.

## Design

Three small pieces, each independently testable.

### Component A: the `tmux-pane-link` script

New executable at `roles/common/files/bin/tmux-pane-link`, deployed to
`~/.local/bin/tmux-pane-link`. Bash, like the surrounding helpers.

**Usage**

```
tmux-pane-link LABEL URL          # set on current pane ($TMUX_PANE)
tmux-pane-link --clear            # clear current pane
tmux-pane-link --pane PANE_ID LABEL URL
tmux-pane-link --pane PANE_ID --clear
```

**Behavior**

- No `$TMUX` set → exit 0 silently. Outside-of-tmux callers (random skills)
  must not error. Same convention as `tmux-agent-worktree`.
- No target pane (`--pane` absent and `$TMUX_PANE` unset) → exit 0 silently.
- `--clear` calls `tmux set-option -pqu -t "$pane" @pane-link` (the same
  unset pattern used by `clear_pane_option` in `worktree-lib.sh` /
  `tmux-agent-worktree`).
- Set path: validate, then write a pre-rendered tmux style string to the
  per-pane user option `@pane-link`:

  ```
  #[hyperlink="<URL>"]<LABEL_ESCAPED>#[hyperlink=]
  ```

  Done via `tmux set-option -pq -t "$pane" @pane-link "<value>"`.

**Validation**

- URL must match `^https?://` (case-insensitive). Reject anything else.
- URL must not contain control characters (`\x00`–`\x1f`, `\x7f`), backslash,
  or double-quote. These either break the OSC 8 sequence or let a hostile
  caller smuggle escape sequences. On reject: print one-line error to stderr,
  exit 2.
- LABEL must not contain control characters. On reject: same as above.
- LABEL `#` characters are doubled to `##` so tmux's format parser does not
  treat them as meta-characters (`#[`, `#{`, `#(` would otherwise be
  interpreted).
- LABEL is also length-limited to 64 chars. Annotations longer than that
  start eating the pane border anyway. Truncate with `…`.

**Quoting in the option value**

The `hyperlink="<URL>"` style argument is parsed by tmux. URLs are rejected
above if they contain `"`, so wrapping the URL in double quotes is
sufficient. No further escaping needed.

### Component B: `pane-border-format` update

Edit both copies of `tmux.conf`:

- `roles/macos/templates/dotfiles/tmux.conf:124`
- `roles/linux/files/dotfiles/tmux.conf:116`

Append `#{?#{@pane-link}, #{@pane-link},}` after the existing label segment
and before the `@pane-last-error` segment. New format (line breaks for
readability — actual config is one line):

```
#{?pane_active,#[bg=black#,fg=colour51],#[bg=black#,fg=colour240]} \
  #{?#{@pane-label},#{@pane-label},#{b:pane_current_path} | #{host_short}}\
  #{?#{@pane-link}, #{@pane-link},}\
  #{?#{@pane-last-error}, #[bg=colour196#,fg=white#,bold] ! #[default],} 
```

The leading space inside the `#{?...,...,}` provides a visual gap between
label and link only when the link is set.

### Component C: clear on `repo-end`

`tmux-agent-worktree`'s `cmd_clear` already runs from `repo-end` and
`tmux-agent-worktree clear`. Add one line at line 219:

```
clear_pane_option "$TMUX_PANE" "@pane-link"
```

No other lifecycle integration. Panes that never went through `repo-start`
won't have `repo-end` clear them — callers in that case must use `--clear`
themselves. Acceptable for v1 (confirmed in brainstorm).

## Caller pattern

Any skill, in any repo:

```bash
tmux-pane-link "GH#$NUM" "https://github.com/$OWNER/$REPO/pull/$NUM"
```

That is the entire contract. The caller does not need to know about
`@pane-link`, `pane-border-format`, OSC 8, or `$TMUX_PANE`.

## Testing

A new bash test at `tests/tmux-pane-link.sh`, in the style of
`tests/tmux-label-contract.sh`. Covers script behavior; the tmux config
re-render is exercised manually once.

**Unit-style cases** (running `tmux-pane-link` directly with `TMUX_PANE`
overridden inside a real tmux session — same approach
`tmux-label-contract.sh` already uses for pane options):

1. Set with valid `http://` URL → `@pane-link` contains
   `#[hyperlink="..."]LABEL#[hyperlink=]`.
2. Set with valid `https://` URL → same shape.
3. Set with `file://`, `javascript:`, scheme-less, or empty URL → exit 2,
   `@pane-link` unchanged.
4. URL containing `\x1b`, `\x07`, backslash, or `"` → exit 2,
   `@pane-link` unchanged.
5. LABEL containing `#` → escaped to `##` in the stored value.
6. LABEL longer than 64 chars → truncated with `…` suffix.
7. `--clear` after a set → `@pane-link` unset.
8. No `$TMUX` → exit 0 silently, no option written.
9. After `tmux-agent-worktree clear`, `@pane-link` is also gone (verifies
   Component C).

**Manual e2e** (one-shot; not in CI):

- Inside Ghostty + tmux, run `tmux-pane-link "GH#1" "https://example.com"`.
- Verify pane border shows ` GH#1 ` after the existing label.
- Hold cmd, click `GH#1`. Browser opens to `https://example.com`.
- Run `tmux-pane-link --clear`. Annotation disappears on next status refresh.

## Risks and mitigations

- **OSC 8 in style string not honored at status refresh.** tmux 3.4+ supports
  this; the local install is 3.6a. If a future tmux regresses, the
  annotation just becomes plain text — no breakage, only loss of
  click-through. Acceptable.
- **Caller smuggles escape sequences via LABEL/URL.** Mitigated by validation
  rules above. The OSC 8 wrapper is constructed by us, not the caller.
- **Status refresh latency.** `pane-border-format` re-renders on
  `status-interval` (60s) plus on hooks the repo already wires. The
  `tmux-pane-link` script calls `tmux refresh-client -S` after writing the
  option so the annotation appears immediately, mirroring
  `refresh_window_label` in `tmux-agent-worktree`.

## Out of scope, listed for clarity

- A second tmux user option with multiple keyed links (e.g. PR + Linear
  ticket on the same pane).
- Replacing the existing `gh pr` shell-out helpers with this primitive.
- Status-bar (top) integration.
- Surfacing in non-Ghostty terminals where OSC 8 is not clickable. The text
  still renders; the click is terminal-dependent.
