#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/roles/macos/files/bin/development-cache-cleanup"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
mkdir -p "$stub_dir"

for tool in npm brew mise docker; do
  cat > "$stub_dir/$tool" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TEST_LOG"
if [ "$(basename "$0")" = mise ] && [ "${1:-}" = cache ]; then
  printf 'mise-cache-age=%s\n' "${MISE_CACHE_PRUNE_AGE:-unset}" >> "$TEST_LOG"
fi
if [ "$(basename "$0")" = docker ] && [ "${1:-}" = context ]; then
  printf '%s\n' "${DOCKER_CONTEXT_HOST:-unix:///var/run/docker.sock}"
fi
if [ "$(basename "$0")" = "${FAIL_TOOL:-}" ]; then
  exit 9
fi
STUB
  chmod +x "$stub_dir/$tool"
done

mise() {
  printf 'mise %s\n' "$*" >> "$TEST_LOG"
  if [ "${1:-}" = cache ]; then
    printf 'mise-cache-age=%s\n' "${MISE_CACHE_PRUNE_AGE:-unset}" >> "$TEST_LOG"
  fi
  [ "${FAIL_TOOL:-}" != mise ]
}
export -f mise

expected="$tmpdir/expected"
cat > "$expected" <<'EXPECTED'
npm cache clean --force
brew cleanup --prune=all
mise cache prune
mise-cache-age=0
mise prune --tools --yes
docker context inspect default --format {{ (index .Endpoints "docker").Host }}
docker --context default image prune --all --force --filter until=336h
docker --context default builder prune --all --force --filter until=336h
EXPECTED

export PATH="$stub_dir:/usr/bin:/bin"
export TEST_LOG="$tmpdir/commands"
export HOME="$tmpdir/home"
mkdir -p "$HOME/Pictures" "$HOME/Library/Caches" \
  "$HOME/Library/Mobile Documents"
touch "$HOME/Pictures/keep" "$HOME/Library/Caches/keep" \
  "$HOME/Library/Mobile Documents/keep"

: > "$TEST_LOG"
bash "$script"
diff -u "$expected" "$TEST_LOG"

: > "$TEST_LOG"
if DOCKER_CONTEXT_HOST=tcp://remote.example:2376 bash "$script"; then
  echo "FAIL: cleanup succeeded with a remote Docker default context" >&2
  exit 1
fi
if grep -q '^docker .* prune' "$TEST_LOG"; then
  echo "FAIL: cleanup pruned a remote Docker context" >&2
  exit 1
fi

: > "$TEST_LOG"
if FAIL_TOOL=npm bash "$script"; then
  echo "FAIL: cleanup succeeded when npm failed" >&2
  exit 1
fi
diff -u "$expected" "$TEST_LOG"

if grep -q -- '--volumes' "$TEST_LOG"; then
  echo "FAIL: cleanup requested Docker volume removal" >&2
  exit 1
fi

for protected_file in \
  "$HOME/Pictures/keep" \
  "$HOME/Library/Caches/keep" \
  "$HOME/Library/Mobile Documents/keep"; do
  if [ ! -f "$protected_file" ]; then
    echo "FAIL: cleanup removed protected data: $protected_file" >&2
    exit 1
  fi
done

echo "development cache cleanup tests passed"
