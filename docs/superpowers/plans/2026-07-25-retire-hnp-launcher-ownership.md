# Retire NMB HNP Launcher Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop NMB from defining or installing `hnp`, remove known NMB-managed deployed copies safely, and preserve HNP-rendered or otherwise unknown launchers.

**Architecture:** Replace the common-role installer with an imported migration task that SHA-256-checks the deployed file before deletion. Keep the retired checksum allowlist at the common-role include boundary so a focused Ansible behavior test can override it with a harmless fixture; then remove NMB's launcher implementation and obsolete behavior artifacts after HNP owns the canonical implementation.

**Tech Stack:** Ansible `include_tasks`, `stat`, and `file` modules; Bash CI harness; Git history and SHA-256 checksums; GitHub Actions.

## Global Constraints

- NMB must contain no executable `hnp` launcher implementation or installer after this work.
- Cleanup must remove only regular files whose SHA-256 matches a known NMB-managed launcher revision.
- Cleanup must preserve HNP-rendered, user-modified, symlinked, directory, absent, and otherwise unknown paths.
- The cleanup behavior test must execute the real Ansible task with a fixture checksum override; it must not retain historical launcher source.
- Remove `tests/hnp.rb`, its workflow step, and the earlier NMB exclusive-attachment spec and plan only after equivalent launcher coverage exists in HNP.
- Do not provision this branch until the coordinated HNP branch has installed the canonical personal-dev launcher on the current machine.
- Use repository-managed files only; never edit `~/.local/bin/hnp` directly.

---

## File Structure

- `roles/common/tasks/retire_hnp_launcher.yml`: reusable migration boundary; stats a configured path and conditionally removes known retired content.
- `roles/common/tasks/main.yml`: replaces the broad `hnp` installer with the cleanup include and the complete historical checksum allowlist.
- `tests/retired-hnp-launcher-cleanup.sh`: executes the real task against temporary known and unknown files, then verifies idempotence.
- `.github/workflows/integration-test.yml`: runs the cleanup regression and stops running retired launcher behavior tests.
- `roles/common/files/bin/hnp`: deleted duplicate launcher implementation.
- `tests/hnp.rb`: deleted launcher behavior suite after its equivalent moves to HNP.
- `docs/superpowers/specs/2026-07-25-hnp-exclusive-tmux-attachment-design.md`: deleted NMB implementation design superseded by HNP ownership.
- `docs/superpowers/plans/2026-07-25-hnp-exclusive-tmux-attachment.md`: deleted NMB implementation plan superseded by HNP ownership.

### Task 1: Add guarded cleanup at the former installer boundary

**Files:**
- Create: `roles/common/tasks/retire_hnp_launcher.yml`
- Create: `tests/retired-hnp-launcher-cleanup.sh`
- Modify: `roles/common/tasks/main.yml:268-273`
- Modify: `.github/workflows/integration-test.yml:25-35`

**Interfaces:**
- Consumes: `nmb_hnp_launcher_path` (absolute string path) and `nmb_retired_hnp_checksums` (array of lowercase SHA-256 strings), supplied by the include caller.
- Produces: removal only when `stat.exists`, `stat.isreg`, and `stat.checksum` matches the configured retired set; otherwise no file mutation.

- [ ] **Step 1: Write the failing Ansible behavior test**

Create executable `tests/retired-hnp-launcher-cleanup.sh` with this complete harness:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
cleanup_tasks="$repo_root/roles/common/tasks/retire_hnp_launcher.yml"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

known_home="$tmp_root/known-home"
unknown_home="$tmp_root/unknown-home"
mkdir -p "$known_home/.local/bin" "$unknown_home/.local/bin"
printf 'retired NMB fixture\n' > "$known_home/.local/bin/hnp"
printf 'HNP-rendered fixture\n' > "$unknown_home/.local/bin/hnp"
known_checksum="$(sha256sum "$known_home/.local/bin/hnp" | cut -d' ' -f1)"

cat > "$tmp_root/playbook.yml" <<YAML
---
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Exercise cleanup for configured retired content
      include_tasks: $cleanup_tasks
      vars:
        nmb_hnp_launcher_path: $known_home/.local/bin/hnp
        nmb_retired_hnp_checksums:
          - $known_checksum

    - name: Exercise cleanup for unknown HNP content
      include_tasks: $cleanup_tasks
      vars:
        nmb_hnp_launcher_path: $unknown_home/.local/bin/hnp
        nmb_retired_hnp_checksums:
          - $known_checksum
YAML

ansible-playbook "$tmp_root/playbook.yml" >/dev/null

test ! -e "$known_home/.local/bin/hnp"
test -f "$unknown_home/.local/bin/hnp"
test "$(cat "$unknown_home/.local/bin/hnp")" = 'HNP-rendered fixture'

ansible-playbook "$tmp_root/playbook.yml" > "$tmp_root/idempotence.log"
rg -F 'changed=0' "$tmp_root/idempotence.log" >/dev/null

echo 'Retired HNP launcher cleanup checks complete'
```

Add a GitHub Actions step immediately after `Verify pinned binary privilege boundary`:

```yaml
      - name: Verify retired HNP launcher cleanup
        run: bash tests/retired-hnp-launcher-cleanup.sh
```

- [ ] **Step 2: Run the behavior test and confirm RED**

Run:

```bash
bash tests/retired-hnp-launcher-cleanup.sh
```

Expected: FAIL because `roles/common/tasks/retire_hnp_launcher.yml` does not exist.

- [ ] **Step 3: Implement the minimal guarded cleanup task**

Create `roles/common/tasks/retire_hnp_launcher.yml`:

```yaml
---

- name: Inspect retired NMB-managed hnp launcher
  stat:
    path: "{{ nmb_hnp_launcher_path }}"
    checksum_algorithm: sha256
  register: nmb_hnp_launcher

- name: Remove retired NMB-managed hnp launcher
  file:
    path: "{{ nmb_hnp_launcher_path }}"
    state: absent
  when:
    - nmb_hnp_launcher.stat.exists
    - nmb_hnp_launcher.stat.isreg | default(false)
    - nmb_hnp_launcher.stat.checksum | default('') in nmb_retired_hnp_checksums
```

Replace the existing `Install hnp script` task in `roles/common/tasks/main.yml` with this include and the seven distinct SHA-256 values obtained from every `roles/common/files/bin/hnp` revision from introduction through `origin/main`:

```yaml
- name: Retire NMB-managed hnp launcher
  include_tasks: retire_hnp_launcher.yml
  vars:
    nmb_hnp_launcher_path: '{{ ansible_facts["user_dir"] }}/.local/bin/hnp'
    nmb_retired_hnp_checksums:
      - 18a2dbe58ffcef1c68cac3754a4f818314ad5a5128bae459cbac4610b88769df
      - 1337de6ecd63aed677f8f11134daf8319057a59aef0d920deee9a4b0ced0ae97
      - 4ffdd21b6a34d18362f7e3301465a23dc14ed884a461e0b3d72422bedf72fbaa
      - 571b2a4df10f75afa3e0930e6037b8c5ebfe6000a82765322c113e5dc657496b
      - 5aacc96a4c27a2cb49f263aae9f5de19f0c4baaeb4534f6b2b40084b90f25d28
      - 6f75fc88577ebd4df6c1c3d2e2c0f7b9b04b766b7d63ad41832215bd1bc5485c
      - 47c77f4e846f8ef4a1d2545f9b5225dafb271a3936e6cd3c5cf053a50bf449ee
```

Before committing, independently reproduce the allowlist from Git history and compare it to the plan:

```bash
for commit in $(git log --format=%H origin/main -- roles/common/files/bin/hnp); do
  git show "$commit:roles/common/files/bin/hnp" 2>/dev/null | sha256sum | cut -d' ' -f1
done | sort -u
```

Expected: exactly the seven hashes above, with no extra or missing value.

- [ ] **Step 4: Run focused GREEN verification**

Run:

```bash
bash tests/retired-hnp-launcher-cleanup.sh
git diff --check
```

Expected: cleanup test prints `Retired HNP launcher cleanup checks complete`; diff check emits no output.

- [ ] **Step 5: Commit the guarded retirement boundary**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Safely retire NMB-managed HNP launchers" \
  roles/common/tasks/retire_hnp_launcher.yml \
  roles/common/tasks/main.yml \
  tests/retired-hnp-launcher-cleanup.sh \
  .github/workflows/integration-test.yml
```

### Task 2: Remove NMB launcher implementation and obsolete artifacts

**Files:**
- Delete: `roles/common/files/bin/hnp`
- Delete: `tests/hnp.rb`
- Delete: `docs/superpowers/specs/2026-07-25-hnp-exclusive-tmux-attachment-design.md`
- Delete: `docs/superpowers/plans/2026-07-25-hnp-exclusive-tmux-attachment.md`
- Modify: `.github/workflows/integration-test.yml:40-43`

**Interfaces:**
- Consumes: the HNP repository's canonical launcher and equivalent behavior coverage, which must exist before these artifacts are removed.
- Produces: an NMB tree with no executable launcher implementation and a CI inventory containing only active tests.

- [ ] **Step 1: Confirm the coordinated HNP branch protects the transferred behavior**

From the HNP worktree, run its launcher behavior and personal-dev shortcut tests named by the coordinated plan. Expected: both pass with zero failures before NMB deletes its duplicate behavior suite.

- [ ] **Step 2: Delete the duplicate implementation and historical implementation documents**

Run:

```bash
rm roles/common/files/bin/hnp
rm tests/hnp.rb
rm docs/superpowers/specs/2026-07-25-hnp-exclusive-tmux-attachment-design.md
rm docs/superpowers/plans/2026-07-25-hnp-exclusive-tmux-attachment.md
```

Remove this exact workflow block from `.github/workflows/integration-test.yml`:

```yaml
      - name: Verify HNP tmux attachment behavior
        run: ruby tests/hnp.rb
```

Do not remove the new `Verify retired HNP launcher cleanup` step.

- [ ] **Step 3: Verify CI inventory and absence of active launcher ownership**

Run:

```bash
bash tests/retired-hnp-launcher-cleanup.sh
bash tests/ci-test-inventory.sh
git grep -n 'roles/common/files/bin/hnp\|Install hnp script\|ruby tests/hnp.rb' -- ':!docs/superpowers/specs/2026-07-25-retire-hnp-launcher-ownership-design.md' ':!docs/superpowers/plans/2026-07-25-retire-hnp-launcher-ownership.md' || true
git diff --check
```

Expected:

- cleanup behavior passes;
- inventory reports `1 passed, 0 failed`;
- grep emits no active source, installer, or workflow reference;
- diff check emits no output.

- [ ] **Step 4: Commit duplicate ownership removal**

```bash
~/.pi/agent/skills/z-commit/commit.sh \
  -m "Remove NMB HNP launcher ownership" \
  roles/common/files/bin/hnp \
  tests/hnp.rb \
  docs/superpowers/specs/2026-07-25-hnp-exclusive-tmux-attachment-design.md \
  docs/superpowers/plans/2026-07-25-hnp-exclusive-tmux-attachment.md \
  .github/workflows/integration-test.yml
```

### Task 3: Verify real provisioning preserves HNP ownership

**Files:**
- No repository file changes expected.

**Interfaces:**
- Consumes: an installed HNP-rendered `~/.local/bin/hnp` from the coordinated HNP branch and NMB's guarded cleanup.
- Produces: empirical proof that NMB provisioning no longer overwrites or deletes the HNP-owned launcher.

- [ ] **Step 1: Confirm the worktree is clean and capture the HNP launcher checksum**

Run:

```bash
git status --short
before_hnp_checksum="$(sha256sum "$HOME/.local/bin/hnp" | cut -d' ' -f1)"
test -n "$before_hnp_checksum"
printf 'before=%s\n' "$before_hnp_checksum"
```

Expected: clean status; installed launcher exists. If the coordinated HNP branch has not yet been provisioned, stop and provision it before continuing.

- [ ] **Step 2: Provision NMB from this feature worktree**

On the current Debian dev host, run:

```bash
bin/provision --become-password-file /home/brian/.config/home-network/hosts-password
```

Expected: play recap reports `failed=0`. Record the `/tmp/provision-*.log` path in the PR verification notes.

- [ ] **Step 3: Verify the HNP-owned launcher survived unchanged**

Run:

```bash
after_hnp_checksum="$(sha256sum "$HOME/.local/bin/hnp" | cut -d' ' -f1)"
printf 'after=%s\n' "$after_hnp_checksum"
test "$after_hnp_checksum" = "$before_hnp_checksum"
bash tests/retired-hnp-launcher-cleanup.sh
bash tests/ci-test-inventory.sh
git diff --check
git status --short
```

Expected: before/after checksums match; focused tests pass; diff/status are clean.

- [ ] **Step 4: Open the coordinated NMB pull request**

Use the repository `pull-request` skill. The PR body must:

- link the coordinated HNP PR under `Related PRs`;
- explain that broad NMB ownership caused last-provision-wins behavior;
- state that cleanup is checksum-guarded and migration-only;
- summarize the real preservation proof and provisioning result;
- avoid claiming stale copies on other machines are removed until NMB provisions there.

After merge, run NMB provisioning once on every machine that previously received the common launcher. Remove the migration task in a later PR only after that convergence is confirmed.
