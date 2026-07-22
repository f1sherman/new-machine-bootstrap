# Tmux-Resurrect Neovim Space-Path Design

## Problem

Tmux-resurrect serializes a pane process as one flat command string. A real reboot snapshot saved the journal editor as:

```text
nvim /Users/brian/Library/Mobile Documents/com~apple~CloudDocs/journal/journal
```

During restore, tmux-resurrect types that command into a shell. The shell treats the space as an argument separator, so Neovim does not reliably reopen the original single path.

## Scope

Fix Neovim restoration when the original command contains exactly one existing file or directory path whose name contains spaces, while preserving upstream stale `nvim -S` fallback behavior.

Do not change restoration for:

- other processes;
- Neovim commands with flags;
- flat argument text that does not resolve as one existing path, including unresolved ambiguous or multiple arguments;
- nonexistent paths;
- Neovim commands already using a local `Session.vim` file, including stale `nvim -S` restore commands that should fall back to plain `nvim` when no session file exists.

When the entire flat text after `nvim ` resolves as one existing path, that path interpretation takes precedence even if the same text could theoretically represent multiple shell arguments.

## Design

Add a repository-managed tmux-resurrect Neovim strategy. Configure both macOS and Linux tmux to select it through `@resurrect-strategy-nvim`.

The strategy receives the original flat command and pane working directory from tmux-resurrect. It will:

1. Return non-`nvim` commands unchanged.
2. Return `nvim -S` when `Session.vim` exists in the pane working directory, preserving current Neovim behavior.
3. When the original command is stale `nvim -S` and no `Session.vim` exists, return plain `nvim` to avoid an immediate restore error.
4. Separate the leading `nvim` token from the remaining flat argument text.
5. Resolve the entire remaining text as one path, relative to the pane working directory when necessary.
6. When that complete path exists, prefer the single-path interpretation and return `nvim` plus a shell-escaped form of the original path text.
7. Otherwise return the original command unchanged.

The strategy will live in repository-managed files and be copied into tmux-resurrect's `strategies` directory after TPM has installed the plugin. Provisioning will manage the same strategy on macOS and Linux.

## Error Handling

The strategy is conservative. Empty arguments, flags, multiple arguments that do not form one existing path, and failed path checks fall back to the original command. An existing path formed by the entire flat argument text is not treated as ambiguous: that single-path interpretation explicitly wins and is escaped.

The output remains a shell command because that is tmux-resurrect's strategy interface. Shell escaping will use Bash's `%q` formatting so the reconstructed single argument survives tmux `send-keys` and shell parsing.

## Testing

Add a standalone contract test for the strategy covering:

- an absolute file path containing spaces;
- a relative directory path containing spaces;
- an ordinary path without spaces;
- a pane directory containing `Session.vim`;
- an existing spaced path whose flat text could theoretically represent multiple arguments, proving the single-path interpretation wins;
- stale `nvim -S` restore commands with no local `Session.vim`, which fall back to plain `nvim`;
- flags or multiple arguments that do not resolve to one path;
- a nonexistent path;
- a non-Neovim command when `Session.vim` exists.

Add configuration assertions that macOS and Linux select the managed strategy, and provisioning inventory assertions that both platform roles install it after tmux-resurrect exists.

## Acceptance Criteria

After saving and restoring a tmux pane running Neovim with one existing space-containing path:

- the restored shell command passes the full path as one argument;
- Neovim opens the intended file or directory;
- existing `Session.vim` restoration remains unchanged, including the stale `nvim -S` fallback when no session file exists;
- unrelated commands and ambiguous Neovim commands that do not resolve as one existing path remain unchanged;
- macOS and Linux provisioning install the strategy idempotently.
