# Design: URL-only PR pane link, rendered first

## Problem

When a pull request is associated with a tmux pane, the pane border shows both
the PR display reference (e.g. `gh#123`) and the full PR URL, in that order,
**after** the branch/repo label:

```
(*branch) repo | host  gh#123 https://github.com/org/repo/pull/123
```

The URL — the only part the terminal makes clickable — sits last. On a narrow
pane it is pushed off the right edge and becomes untruncated/unclickable. The
`gh#123` reference is redundant noise that consumes the space the URL needs.

## Related PRs

- Number + URL both shown: introduced by #203, which changed `@pane-link` to
  store the combined display label and URL.
- Link rendered after the branch label: introduced by #187, which first added
  `@pane-link` to `pane-border-format` after `@pane-label`.

## Goal

- Drop the PR display reference (`gh#123`) entirely.
- Render the bare PR URL **first** in the pane border, ahead of the branch/repo
  label, so the full clickable URL is always visible.

Target border layout:

```
https://github.com/org/repo/pull/123 (*branch) repo | host  !
```

(URL, then branch/repo label, then the existing error indicator.)

## Out of scope

- The missing `(*branch)` parens / `*` dirty marker is a separate concern and is
  not addressed here.

## Current flow

1. `roles/common/files/bin/tmux-agent-worktree`
   - `cached_pr_pane_link_for_path()` reads the PR-status cache, validates the
     row is an open PR whose `display_ref` matches `^(gh|fj)#[0-9]+$`, and emits
     `[display_ref, html_url]` as TSV.
   - `publish_cached_pr_pane_link_for_path()` splits that TSV into
     `display_ref` + `url` and calls
     `tmux-pane-link --pane "$pane_id" "$display_ref" "$url"`.
2. `roles/common/files/bin/tmux-pane-link`
   - Takes `label` + `url` positionals, stores `@pane-link = "$label $url"`
     (line 86: `value="$label $url_escaped"`).
3. `roles/macos/templates/dotfiles/tmux.conf:124` and
   `roles/linux/files/dotfiles/tmux.conf:116`
   - `pane-border-format` renders, in order: color, space, branch-label (or
     `cwd | host` fallback), then ` #{@pane-link}`, then the error indicator.

## Changes

### 1. `roles/common/files/bin/tmux-pane-link` — store the URL only

- Drop the `label` positional. New invocation shape:
  `tmux-pane-link [--pane P] [--clear] <url>`.
- Set `value="$url_escaped"` (was `"$label $url_escaped"`).
- Remove the now-dead label-length-truncation block and the `label` `#`-escaping
  line (current lines 79–84) along with the `label` positional read.
- Update the header comment, which currently describes a "label + URL
  annotation", to describe a URL-only annotation.
- Keep all URL validation (scheme check, forbidden-character check), `--clear`
  handling, `@pane-link-source` clearing, and the state-dir vs. tmux-option
  storage split unchanged.

### 2. `roles/common/files/bin/tmux-agent-worktree` — stop passing the number

- In `cached_pr_pane_link_for_path()`, keep the
  `select($display_ref | test("^(gh|fj)#[0-9]+$"))` guard (it confirms the cache
  row is a real PR) but output only `$html_url` instead of the
  `[display_ref, html_url] | @tsv`.
- In `publish_cached_pr_pane_link_for_path()`, the returned value is now just the
  URL: drop the TSV split, set `url="$link"`, guard on empty `$url`, and call
  `tmux-pane-link --pane "$pane_id" "$url"`.
- No change to the cache-source bookkeeping (`@pane-link-source`,
  clear-on-failure paths).

### 3. tmux.conf (macOS + Linux) — render the link first

In both `roles/macos/templates/dotfiles/tmux.conf:124` and
`roles/linux/files/dotfiles/tmux.conf:116`, reorder `pane-border-format` so the
`@pane-link` block precedes the branch-label block.

- The link block changes from a leading-space form
  `#{?#{@pane-link}, #{@pane-link},}` to a trailing-space form
  `#{?#{@pane-link},#{@pane-link} ,}`, and moves to immediately after the
  leading color+space, before the `@pane-label` block.
- The branch-label block and the error block are otherwise unchanged.

Resulting order: `{color} {space} {URL + trailing space when present} {branch
label or cwd|host} {error} {trailing space}`.

## Verification

There is no automated test suite for these scripts; verify empirically:

1. Provision the worktree's changes (or point `PATH`/tmux.conf at the worktree
   copies), associate a pane with a branch that has an open PR in the cache, and
   confirm the pane border shows the bare URL **first**, with no `gh#`/`fj#`
   prefix, and the full URL is clickable on a narrow pane.
2. Confirm the branch/repo label still renders after the URL.
3. Confirm `tmux-pane-link --clear` (and `tmux-agent-worktree` clear paths) still
   remove `@pane-link` and `@pane-link-source`.
4. Confirm a pane with no associated PR is unchanged (branch label only).
