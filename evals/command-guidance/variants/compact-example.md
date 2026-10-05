For user copy-paste commands, keep lines ≤80 characters; no visual wrapping or heredocs. Continue with `\` only between complete arguments, never inside paths, URLs, quotes, or `--opt=value`/`key=value`. For arguments over ~60 characters, use a short variable with quoted expansion (`"$f"`); build longer values with `printf` or successive assignments. Quoted newlines are allowed only as whitespace in programs such as jq/awk, never inside paths or data values. Before sending, remove each `\`-newline mentally, retain indentation, and check every argument is intact.

Keep option values attached:
```bash
kubectl get pod example \
  -o jsonpath='{.metadata.name}'
```
