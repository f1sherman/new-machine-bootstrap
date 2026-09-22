#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
linker="$repo_root/roles/common/files/bin/link-managed-skill-tree"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

source_one="$tmp_root/source one"
source_two="$tmp_root/source two"
target_one="$tmp_root/target one"
target_two="$tmp_root/target two"
mkdir -p \
  "$source_one/shared" \
  "$source_one/overlaid" \
  "$source_one/excluded" \
  "$source_two/overlaid" \
  "$target_one/overlaid" \
  "$target_one/unmanaged" \
  "$target_two"
printf 'shared\n' >"$source_one/shared/SKILL.md"
printf '#!/bin/sh\n' >"$source_one/shared/run.sh"
chmod 0755 "$source_one/shared/run.sh"
printf 'base\n' >"$source_one/overlaid/SKILL.md"
printf 'excluded source\n' >"$source_one/excluded/SKILL.md"
printf 'old managed copy\n' >"$target_one/overlaid/SKILL.md"
printf 'keep excluded\n' >"$target_one/excluded"
printf 'keep me\n' >"$target_one/unmanaged/SKILL.md"
printf 'specific\n' >"$source_two/overlaid/SKILL.md"

first_output="$(
  "$linker" --exclude excluded "$source_one" "$target_one" "$target_two"
)"
test "$first_output" = changed
for target in "$target_one" "$target_two"; do
  test -L "$target/shared"
  test -L "$target/overlaid"
  test "$(cat "$target/shared/SKILL.md")" = shared
  test "$(cat "$target/overlaid/SKILL.md")" = base
  test -x "$target/shared/run.sh"
done
test "$(cat "$target_one/unmanaged/SKILL.md")" = 'keep me'
test "$(cat "$target_one/excluded")" = 'keep excluded'
test ! -e "$target_two/excluded"

second_output="$(
  "$linker" --exclude excluded "$source_one" "$target_one" "$target_two"
)"
test "$second_output" = unchanged

overlay_output="$("$linker" "$source_two" "$target_one")"
test "$overlay_output" = changed
test -L "$target_one/overlaid"
test "$(cat "$target_one/overlaid/SKILL.md")" = specific
test "$(cat "$target_one/unmanaged/SKILL.md")" = 'keep me'

overlay_repeat_output="$("$linker" "$source_two" "$target_one")"
test "$overlay_repeat_output" = unchanged

printf 'Managed skill tree linking passed\n'
