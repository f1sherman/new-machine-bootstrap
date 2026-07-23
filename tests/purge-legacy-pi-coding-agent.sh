#!/usr/bin/env bash
# Behavioral test for roles/common/files/bin/purge-legacy-pi-coding-agent:
# the legacy @mariozechner pi (package dir + shadowing `pi` symlink) is removed
# from every scanned Node prefix, the managed @earendil-works pi is left intact,
# and a second run is a no-op.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
purge="$repo_root/roles/common/files/bin/purge-legacy-pi-coding-agent"

pass=0
fail=0
pass_case() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
fail_case() { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; printf '      %s\n' "$2"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A stale Node prefix carrying the legacy package + a `pi` symlink into it.
legacy_prefix="$tmp/node/22.0.0"
mkdir -p "$legacy_prefix/bin" "$legacy_prefix/lib/node_modules/@mariozechner/pi-coding-agent/dist"
printf '#!/usr/bin/env node\n' >"$legacy_prefix/lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
ln -s "../lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js" "$legacy_prefix/bin/pi"

# A managed prefix that MUST survive: @earendil-works package + its own `pi`.
managed_prefix="$tmp/managed"
mkdir -p "$managed_prefix/bin" "$managed_prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist"
printf '#!/usr/bin/env node\n' >"$managed_prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
ln -s "../lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" "$managed_prefix/bin/pi"

globs="$legacy_prefix $managed_prefix"

first="$(PI_LEGACY_PREFIX_GLOBS="$globs" bash "$purge")"

if [ ! -e "$legacy_prefix/lib/node_modules/@mariozechner/pi-coding-agent" ]; then
  pass_case "legacy package directory removed"
else
  fail_case "legacy package directory removed" "still present"
fi

if [ ! -e "$legacy_prefix/lib/node_modules/@mariozechner" ]; then
  pass_case "emptied legacy scope directory removed"
else
  fail_case "emptied legacy scope directory removed" "still present"
fi

if [ ! -L "$legacy_prefix/bin/pi" ] && [ ! -e "$legacy_prefix/bin/pi" ]; then
  pass_case "shadowing legacy pi symlink removed"
else
  fail_case "shadowing legacy pi symlink removed" "still present"
fi

if [ -e "$managed_prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" ] \
  && [ -L "$managed_prefix/bin/pi" ]; then
  pass_case "managed @earendil-works pi left intact"
else
  fail_case "managed @earendil-works pi left intact" "managed install was disturbed"
fi

if [ "$first" = "changed" ]; then
  pass_case "reports changed on first run"
else
  fail_case "reports changed on first run" "got: $first"
fi

second="$(PI_LEGACY_PREFIX_GLOBS="$globs" bash "$purge")"
if [ "$second" = "unchanged" ]; then
  pass_case "idempotent: reports unchanged on second run"
else
  fail_case "idempotent: reports unchanged on second run" "got: $second"
fi

# A managed pi that is the only thing on PATH must never be reported/removed.
managed_only="$tmp/managed-only"
mkdir -p "$managed_only/bin" "$managed_only/lib/node_modules/@earendil-works/pi-coding-agent/dist"
ln -s "../lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" "$managed_only/bin/pi"
managed_run="$(PI_LEGACY_PREFIX_GLOBS="$managed_only" bash "$purge")"
if [ "$managed_run" = "unchanged" ] && [ -L "$managed_only/bin/pi" ]; then
  pass_case "no-op against a managed-only prefix"
else
  fail_case "no-op against a managed-only prefix" "got: $managed_run"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
