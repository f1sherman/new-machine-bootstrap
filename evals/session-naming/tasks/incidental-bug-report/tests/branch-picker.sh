#!/usr/bin/env bash
set -euo pipefail
picker="${BRANCH_PICKER:-/workspace/bin/git-switch-branch}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/outside" "$tmp/repo" "$tmp/bin"
set +e
(cd "$tmp/outside" && bash "$picker") > "$tmp/stdout" 2> "$tmp/stderr"
status=$?
set -e
if [ "$status" -eq 0 ]; then
  echo "FAIL: branch picker returned success outside a Git repository" >&2
  exit 1
fi
git -C "$tmp/repo" init -q -b main
git -C "$tmp/repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
git -C "$tmp/repo" branch topic
printf '#!/usr/bin/env bash\ngrep "topic"\n' > "$tmp/bin/fzf"
chmod +x "$tmp/bin/fzf"
result="$(cd "$tmp/repo" && PATH="$tmp/bin:$PATH" bash "$picker")"
[ "$result" = $'checkout\ttopic' ]
echo "Branch picker failure status and normal branch selection passed"
