# Z-Prefixed Pi Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prefix every NMB-managed Pi skill with `z-` so Pi autocomplete groups the custom commands together.

**Architecture:** Rename each managed Pi source directory and matching frontmatter name, while leaving Claude, Codex, package, and upstream skills unchanged. Extend the existing Ruby contract test to enforce the naming convention and the explicit Ansible migration that removes old unprefixed deployed directories.

**Tech Stack:** Ruby contract tests, Ansible YAML, Markdown skill frontmatter, shell verification.

## Global Constraints

- Every repository-managed Pi skill under `roles/common/files/config/skills/pi/` must prepend `z-` to its existing name.
- Each Pi skill frontmatter `name` must equal its directory name.
- Claude and Codex skill names remain unchanged.
- Third-party and package-provided Pi skills remain unchanged.
- Provisioning removes old unprefixed managed directories without aliases, inference, or dual-name compatibility.
- Do not modify deployed files outside this repository directly; apply managed changes with `bin/provision`.

---

### Task 1: Rename Managed Pi Skill Sources

**Files:**
- Modify: `tests/pi-shared-skills.rb`
- Rename: every directory directly under `roles/common/files/config/skills/pi/` by prepending `z-`
- Modify: every renamed `roles/common/files/config/skills/pi/z-*/SKILL.md`
- Modify: `roles/common/files/config/skills/pi/z-commit/SKILL.md`
- Modify: `roles/common/tasks/main.yml:2284-2295`

**Interfaces:**
- Consumes: shared skill directory names under `roles/common/files/config/skills/{common,claude,codex}/`
- Produces: managed Pi directories and frontmatter names in the form `z-approve-spec`, `z-commit`, and the other `z-` counterparts

- [ ] **Step 1: Change the contract test to require `z-` names**

Replace the expected-name calculation, per-skill prefix checks, commit-helper path, and success text in `tests/pi-shared-skills.rb` with:

```ruby
expected_pi_names = source_skill_dirs.map do |path|
  "z-#{File.basename(path).sub(/^_/, "")}"
end.uniq.sort
actual_pi_names = Dir.children(pi_root).select { |name| File.directory?(File.join(pi_root, name)) }.sort

abort "Pi shared skills do not match z-prefixed Claude/Codex/common counterparts\nExpected: #{expected_pi_names.inspect}\nActual:   #{actual_pi_names.inspect}" unless actual_pi_names == expected_pi_names

actual_pi_names.each do |name|
  abort "Pi skill name must start with z-: #{name}" unless name.start_with?("z-")

  skill_file = File.join(pi_root, name, "SKILL.md")
  abort "Missing SKILL.md for #{name}" unless File.file?(skill_file)

  contents = File.read(skill_file)
  frontmatter = contents[/\A---\n(.*?)\n---\n/m, 1]
  abort "Missing YAML frontmatter for #{name}" unless frontmatter

  metadata = YAML.safe_load(frontmatter)
  abort "Frontmatter name for #{name} must equal directory name, got #{metadata["name"].inspect}" unless metadata["name"] == name
  abort "Pi skill frontmatter name must start with z-: #{name}" unless metadata["name"].start_with?("z-")
end

commit_helper = File.join(pi_root, "z-commit", "commit.sh")
abort "Missing Pi commit helper" unless File.file?(commit_helper)
abort "Pi commit helper must be executable" unless File.executable?(commit_helper)

puts "PASS  z-prefixed Pi skills mirror NMB Claude/Codex/common skill counterparts"
```

- [ ] **Step 2: Run the contract test and verify the new expectation fails**

Run:

```bash
ruby tests/pi-shared-skills.rb
```

Expected: failure beginning `Pi shared skills do not match z-prefixed Claude/Codex/common counterparts`, with expected names beginning `z-` and actual names still unprefixed.

- [ ] **Step 3: Rename all managed Pi skill directories**

Run from the repository root:

```bash
for skill_dir in roles/common/files/config/skills/pi/*; do
  skill_name=${skill_dir##*/}
  git mv "$skill_dir" "roles/common/files/config/skills/pi/z-$skill_name"
done
```

Expected: all 18 managed directories are now named `z-*`; `find roles/common/files/config/skills/pi -mindepth 1 -maxdepth 1 -type d` returns no unprefixed directory.

- [ ] **Step 4: Prefix every Pi skill frontmatter name**

Run:

```bash
ruby -e '
Dir.glob("roles/common/files/config/skills/pi/z-*/SKILL.md").each do |path|
  contents = File.read(path)
  contents.sub!(/^name: (?!z-)(.+)$/, "name: z-\\1")
  File.write(path, contents)
end
'
```

Then verify:

```bash
for skill_file in roles/common/files/config/skills/pi/z-*/SKILL.md; do
  directory_name=$(basename "$(dirname "$skill_file")")
  frontmatter_name=$(awk '/^name:/{print $2; exit}' "$skill_file")
  test "$frontmatter_name" = "$directory_name" || exit 1
done
```

Expected: exit status 0.

- [ ] **Step 5: Update the exact managed commit-helper references**

In `roles/common/files/config/skills/pi/z-commit/SKILL.md`, change:

```markdown
`~/.pi/agent/skills/commit/commit.sh`
```

to:

```markdown
`~/.pi/agent/skills/z-commit/commit.sh`
```

In `roles/common/tasks/main.yml`, change the Pi helper copy paths to:

```yaml
- name: Install Pi commit helper to ~/.pi/agent/skills
  copy:
    src: '{{ playbook_dir }}/roles/common/files/config/skills/pi/z-commit/commit.sh'
    dest: '{{ ansible_facts["user_dir"] }}/.pi/agent/skills/z-commit/commit.sh'
    mode: '0755'
```

Do not change the generic skill-name installation examples in the conversion skills; they describe user-selected output rather than a repository-managed skill name.

- [ ] **Step 6: Run the renamed-source contract test**

Run:

```bash
ruby tests/pi-shared-skills.rb
```

Expected: `PASS  z-prefixed Pi skills mirror NMB Claude/Codex/common skill counterparts`.

- [ ] **Step 7: Commit the source rename**

Run the managed commit helper available to the current session:

```bash
~/.pi/agent/skills/commit/commit.sh -m "Prefix managed Pi skills with z" \
  roles/common/files/config/skills/pi \
  roles/common/tasks/main.yml \
  tests/pi-shared-skills.rb
```

Expected: one commit containing only the source renames, frontmatter changes, reference updates, and naming contract.

---

### Task 2: Remove Old Unprefixed Deployed Skills

**Files:**
- Modify: `tests/pi-shared-skills.rb`
- Modify: `roles/common/tasks/main.yml:2227-2242`

**Interfaces:**
- Consumes: the logical shared skill names derived by `tests/pi-shared-skills.rb`
- Produces: an explicit Ansible cleanup list containing every formerly deployed unprefixed managed Pi skill directory

- [ ] **Step 1: Add a cleanup-list contract test**

After `actual_pi_names` is assigned in `tests/pi-shared-skills.rb`, add:

```ruby
legacy_pi_names = expected_pi_names.map { |name| name.delete_prefix("z-") }
tasks_file = File.read(File.join(repo_root, "roles/common/tasks/main.yml"))
cleanup_block = tasks_file[/^- name: Remove deleted managed Pi skills\n.*?(?=^- name:)/m]
abort "Missing managed Pi skill cleanup task" unless cleanup_block

missing_cleanup_names = legacy_pi_names.reject do |name|
  cleanup_block.match?(/^    - #{Regexp.escape(name)}$/)
end
abort "Managed Pi cleanup task is missing old names: #{missing_cleanup_names.inspect}" unless missing_cleanup_names.empty?
```

- [ ] **Step 2: Run the contract test and verify cleanup coverage fails**

Run:

```bash
ruby tests/pi-shared-skills.rb
```

Expected: failure beginning `Managed Pi cleanup task is missing old names:` and listing active unprefixed skill names such as `approve-spec` and `commit`.

- [ ] **Step 3: Extend the explicit Ansible cleanup list**

Keep the existing retired names and add every formerly deployed active name so the task is:

```yaml
- name: Remove deleted managed Pi skills
  file:
    path: '{{ ansible_facts["user_dir"] }}/.pi/agent/skills/{{ item }}'
    state: absent
  loop:
    - validate-plan
    - create-plan
    - implement-plan
    - research-codebase
    - approve-spec
    - catchup
    - commit
    - convert-skill-from-claude
    - convert-skill-from-codex
    - create-handoff
    - create-ics
    - deep-research
    - fix
    - generate-codex-auth
    - humanizer
    - macos-keychain-secrets
    - recover-agent-sessions
    - resume-claude-session
    - resume-codex-session
    - resume-handoff
    - spec-first
    - spec-to-pr
```

- [ ] **Step 4: Run focused verification**

Run:

```bash
ruby tests/pi-shared-skills.rb
git diff --check
```

Expected: Ruby test passes with the `z-prefixed` success message; `git diff --check` exits 0 with no output.

- [ ] **Step 5: Commit the migration cleanup**

Run:

```bash
~/.pi/agent/skills/commit/commit.sh -m "Remove old unprefixed Pi skill paths" \
  roles/common/tasks/main.yml \
  tests/pi-shared-skills.rb
```

Expected: one commit containing the cleanup contract and explicit Ansible migration list.

- [ ] **Step 6: Apply provisioning and verify deployed state**

Run:

```bash
bin/provision
```

Expected: provisioning completes without failed tasks.

Then run:

```bash
ruby tests/pi-shared-skills.rb
legacy_names=$(find roles/common/files/config/skills/pi -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's/^z-//' | sort)
for name in $legacy_names; do
  test ! -e "$HOME/.pi/agent/skills/$name" || exit 1
done
for source_dir in roles/common/files/config/skills/pi/z-*; do
  name=${source_dir##*/}
  test -f "$HOME/.pi/agent/skills/$name/SKILL.md" || exit 1
done
test -x "$HOME/.pi/agent/skills/z-commit/commit.sh"
```

Expected: the Ruby test prints `PASS`; all shell checks exit 0, proving old unprefixed managed paths are absent and all renamed skills plus the executable commit helper are deployed.

- [ ] **Step 7: Verify the final branch diff**

Run:

```bash
git status --short --untracked-files=no
git diff --check HEAD~2..HEAD
git diff --stat main...HEAD
```

Expected: no tracked uncommitted changes; no whitespace errors; the branch contains the design, plan, renamed Pi skills, test changes, and Ansible migration only.
