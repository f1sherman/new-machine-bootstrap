#!/usr/bin/env bash
# Behavioral test for roles/common/files/bin/purge-legacy-pi-coding-agent:
# both package identities that can shadow the mise-managed npm tool are removed
# from scanned global prefixes, unrelated content survives, and reruns are no-ops.
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

# Separate scanned per-Node prefixes exercise each stale package identity and
# its corresponding bin/pi link.
mario_prefix="$tmp/node/20.0.0"
mkdir -p "$mario_prefix/bin" "$mario_prefix/lib/node_modules/@mariozechner/pi-coding-agent/dist"
printf '#!/usr/bin/env node\n' >"$mario_prefix/lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
ln -s "../lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js" "$mario_prefix/bin/pi"

earendil_prefix="$tmp/node/22.0.0"
mkdir -p "$earendil_prefix/bin" "$earendil_prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist"
printf '#!/usr/bin/env node\n' >"$earendil_prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
ln -s "../lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" "$earendil_prefix/bin/pi"

# A scanned prefix with stale packages but an unrelated pi link. The packages
# must be removed without disturbing the link or unrelated same-scope packages.
preserved_prefix="$tmp/homebrew"
mkdir -p \
  "$preserved_prefix/bin" \
  "$preserved_prefix/lib/node_modules/@mariozechner/pi-coding-agent" \
  "$preserved_prefix/lib/node_modules/@mariozechner/other-package" \
  "$preserved_prefix/lib/node_modules/@earendil-works/pi-coding-agent" \
  "$preserved_prefix/lib/node_modules/@earendil-works/other-package" \
  "$preserved_prefix/lib/node_modules/other-package/dist"
printf '#!/usr/bin/env node\n' >"$preserved_prefix/lib/node_modules/other-package/dist/pi.js"
ln -s "../lib/node_modules/other-package/dist/pi.js" "$preserved_prefix/bin/pi"

# The managed mise npm-tool root is intentionally outside the scanned prefix
# list and must remain untouched.
managed_root="$tmp/mise/installs/npm-earendil-works-pi-coding-agent/0.80.10"
mkdir -p "$managed_root/bin" "$managed_root/node_modules/@earendil-works/pi-coding-agent/dist"
printf '#!/usr/bin/env node\n' >"$managed_root/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
ln -s "../node_modules/@earendil-works/pi-coding-agent/dist/cli.js" "$managed_root/bin/pi"

globs="$mario_prefix $earendil_prefix $preserved_prefix"
first="$(PI_LEGACY_PREFIX_GLOBS="$globs" bash "$purge")"

for package_path in \
  "$mario_prefix/lib/node_modules/@mariozechner/pi-coding-agent" \
  "$earendil_prefix/lib/node_modules/@earendil-works/pi-coding-agent" \
  "$preserved_prefix/lib/node_modules/@mariozechner/pi-coding-agent" \
  "$preserved_prefix/lib/node_modules/@earendil-works/pi-coding-agent"
do
  if [ ! -e "$package_path" ]; then
    pass_case "stale package removed: ${package_path#"$tmp"/}"
  else
    fail_case "stale package removed: ${package_path#"$tmp"/}" "still present"
  fi
done

for scope_path in \
  "$mario_prefix/lib/node_modules/@mariozechner" \
  "$earendil_prefix/lib/node_modules/@earendil-works"
do
  if [ ! -e "$scope_path" ]; then
    pass_case "emptied scope removed: ${scope_path#"$tmp"/}"
  else
    fail_case "emptied scope removed: ${scope_path#"$tmp"/}" "still present"
  fi
done

for pi_link in "$mario_prefix/bin/pi" "$earendil_prefix/bin/pi"; do
  if [ ! -L "$pi_link" ] && [ ! -e "$pi_link" ]; then
    pass_case "shadowing pi link removed: ${pi_link#"$tmp"/}"
  else
    fail_case "shadowing pi link removed: ${pi_link#"$tmp"/}" "still present"
  fi
done

if [ -d "$preserved_prefix/lib/node_modules/@mariozechner/other-package" ] \
  && [ -d "$preserved_prefix/lib/node_modules/@earendil-works/other-package" ]; then
  pass_case "unrelated same-scope packages preserved"
else
  fail_case "unrelated same-scope packages preserved" "an unrelated package was removed"
fi

if [ -L "$preserved_prefix/bin/pi" ] \
  && [ "$(readlink "$preserved_prefix/bin/pi")" = "../lib/node_modules/other-package/dist/pi.js" ]; then
  pass_case "unrelated pi link preserved"
else
  fail_case "unrelated pi link preserved" "unrelated link was removed or changed"
fi

if [ -e "$managed_root/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" ] \
  && [ -L "$managed_root/bin/pi" ]; then
  pass_case "mise npm-tool install root outside scanned prefixes preserved"
else
  fail_case "mise npm-tool install root outside scanned prefixes preserved" "managed install was disturbed"
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
