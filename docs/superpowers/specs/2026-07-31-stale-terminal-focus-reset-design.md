# Stale Terminal Focus Reset Design

## Problem

A foreground TUI or remote SSH process can exit abnormally while DEC focus reporting mode 1004 is enabled. When control returns to Zsh, tmux continues to send focus-in and focus-out sequences to the pane. Zsh can treat these sequences as invalid line-editor input and emit a terminal bell. The bell makes the tmux window alert recur immediately after the user selects it.

## Design

Add one managed Zsh `precmd` hook that writes the DEC private-mode reset sequence `\e[?1004l` to the interactive terminal. The hook runs when control returns to the shell prompt, after the foreground process has exited. It does not run while a TUI is active. A later TUI can enable focus reporting when it starts.

Keep tmux focus events and bell monitoring enabled. Those features are correct and useful. Do not suppress Zsh bells or add alert-clearing heuristics.

## Testing

Add a shell contract test that sources the managed Zsh fragment with a stubbed `add-zsh-hook`, calls the focus-reset function, and verifies the exact bytes written. Verify that the function is registered as a `precmd` hook. Run the focused test, the existing shell and tmux contract tests, and provisioning. After provisioning, enable focus reporting in a test pane, return to the prompt, switch away, and verify that tmux does not set the bell flag.
