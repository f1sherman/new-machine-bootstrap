For user copy-paste commands. No heredocs or visual wrapping. Put `\` continuations between complete arguments only, never inside paths, URLs, quoted strings, or `--opt=value`/`key=value`. Store arguments over ~60 characters in variables named f or url (not Zsh’s path); expand them quoted (`"$f"`). Literal quoted newlines are allowed only where jq/awk treats them as program whitespace, never inside paths or data values. Before sending, remove `\`-newlines mentally, retain indentation, and verify intact arguments.

Build long values across short assignments:
```bash
f="$HOME/.config/rendered"
f="$f/production/application/settings.yaml"
cat "$f"
```
