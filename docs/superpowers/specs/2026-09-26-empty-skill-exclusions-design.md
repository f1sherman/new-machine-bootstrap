# Empty Skill Exclusions Fix Design

Status: Self-approved

## Goal

Make `link-managed-skill-tree` work on macOS Bash 3.2 when no `--exclude`
arguments are supplied, so provisioning can continue.

## Root cause

The script enables `set -u` and expands an initialized but empty array with
`"${excluded_skills[@]}"`. Bash 3.2 reports that expansion as an unbound
variable. Newer Bash versions accept it, so Linux CI did not expose the failure.
The existing behavioral test already reproduces it on the target Mac.

## Approach

Return `1` from `is_excluded` before the array expansion when the exclusion
array length is zero. Preserve all non-empty exclusion behavior.

Alternatives such as removing `set -u` weaken the script globally. Shell-specific
expansion syntax is less clear than an explicit empty-list guard.

## Verification

Run `tests/link-managed-skill-tree.sh`, shell syntax checks, Ansible syntax, and
diff checks. Then open a separate pull request. After merge, rerun the original
provisioning workflow.
