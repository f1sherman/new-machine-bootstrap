#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$repo_root/roles/macos/files/bin/herdr-launch"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/home/.local/bin"
mkdir -p "$stub_dir"
cat > "$stub_dir/herdr" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${TMUX+x}" = x ]; then printf 'TMUX=present\n' >> "$TEST_LOG"; else printf 'TMUX=absent\n' >> "$TEST_LOG"; fi
if [ "${TMUX_PANE+x}" = x ]; then printf 'TMUX_PANE=present\n' >> "$TEST_LOG"; else printf 'TMUX_PANE=absent\n' >> "$TEST_LOG"; fi
printf 'PRESERVED_VALUE=%s\n' "${PRESERVED_VALUE:-absent}" >> "$TEST_LOG"
printf 'args=%s\n' "$*" >> "$TEST_LOG"
STUB
chmod +x "$stub_dir/herdr"

expected="$tmpdir/expected"
cat > "$expected" <<'EXPECTED'
TMUX=absent
TMUX_PANE=absent
PRESERVED_VALUE=present
args=alpha beta
EXPECTED

export PATH="/usr/bin:/bin"
export HOME="$tmpdir/home"
export TEST_LOG="$tmpdir/commands"
TMUX=stale TMUX_PANE=%2 PRESERVED_VALUE=present \
  bash "$launcher" alpha beta

diff -u "$expected" "$TEST_LOG"
printf 'herdr launcher tests passed\n'
