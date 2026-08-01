# macOS Pi Aube Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make macOS provisioning resolve the managed Pi package from the current Aube-backed mise npm layout.

**Architecture:** Both managed Pi tasks will validate the nested package manifest and use its direct `dist/cli.js` executable. Linux retains its existing executable-link fallback, while macOS uses the explicit current nested layout. The package-link task receives the validated package root instead of deriving it from a missing macOS launcher.

**Tech Stack:** Ansible YAML, Bash, Ruby contract tests

## Global Constraints

- Use `<mise-root>/node_modules/@earendil-works/pi-coding-agent` as the primary managed package path on macOS and Linux.
- Link `~/.local/bin/pi` to the direct package executable, not `node_modules/.bin/pi`.
- Keep the existing Linux `<mise-root>/bin/pi` fallback.
- Reject missing, malformed, wrong-name, wrong-version, or non-executable managed packages.
- Preserve stale managed-symlink replacement and refusal to overwrite non-symlink destinations.

---

### Task 1: Resolve the current macOS Aube package layout

**Files:**
- Modify: `tests/pi-aube-install-layout-contract.rb`
- Modify: `roles/common/tasks/main.yml:1405-1498`

**Interfaces:**
- Consumes: `mise where npm:@earendil-works/pi-coding-agent`, the pinned `tool_versions.runtimes.pi_coding_agent`, and `ansible_facts['os_family']`.
- Produces: `pi_package_root` as the validated package directory and `pi_bin` as its executable `dist/cli.js`.

- [ ] **Step 1: Write the failing macOS layout contract**

Update the task assertions so the shared primary resolver must appear before the Linux-only fallback. Extract that resolver and execute it against a fixture with this structure:

```text
mise-install/
  node_modules/
    .bin/pi
    @earendil-works/pi-coding-agent/
      package.json
      dist/cli.js
```

Require output equal to:

```text
<mise-install>/node_modules/@earendil-works/pi-coding-agent/dist/cli.js
<mise-install>/node_modules/@earendil-works/pi-coding-agent
```

Also require both managed Pi tasks to link or export the direct executable rather than `node_modules/.bin/pi`.

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
```

Expected: failure stating that the macOS task still selects `<mise-root>/bin/pi` or does not expose the validated nested package root.

- [ ] **Step 3: Implement the shared primary resolver**

In both tasks, resolve and validate the nested package first:

```bash
pi_package_root="$pi_root/node_modules/@earendil-works/pi-coding-agent"
pi_manifest="$pi_package_root/package.json"
if [[ ! -f "$pi_manifest" && "{{ ansible_facts['os_family'] }}" != "Darwin" ]]; then
  pi_launcher="$pi_root/bin/pi"
  pi_bin="$(realpath "$pi_launcher")" || { echo "Managed Pi package could not be resolved from nested package or executable: $pi_package_root, $pi_launcher" >&2; exit 1; }
  pi_package_root="$(dirname "$(dirname "$pi_bin")")"
  pi_manifest="$pi_package_root/package.json"
fi
pi_name="$(jq -er '.name | select(type == "string")' "$pi_manifest")" || { echo "Managed Pi package manifest is missing a string name: $pi_manifest" >&2; exit 1; }
pi_version="$(jq -er '.version | select(type == "string")' "$pi_manifest")" || { echo "Managed Pi package manifest is missing a string version: $pi_manifest" >&2; exit 1; }
[[ "$pi_name" == '@earendil-works/pi-coding-agent' && "$pi_version" == "{{ tool_versions.runtimes.pi_coding_agent }}" ]] || { echo "Managed Pi package manifest has unexpected identity or version: $pi_manifest" >&2; exit 1; }
pi_bin="$pi_package_root/dist/cli.js"
```

In the package-link task, always export `PI_PACKAGE_ROOT`. Simplify the Ruby block to:

```ruby
package_root = Pathname.new(ENV.fetch("PI_PACKAGE_ROOT")).realpath
```

Keep the existing executable and package-directory checks.

- [ ] **Step 4: Verify GREEN and repository syntax**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
ruby tests/pi-managed-aube-update-contract.rb
ruby -e 'require "yaml"; YAML.load_file("roles/common/tasks/main.yml"); puts "YAML valid"'
git diff --check
```

Expected: both contracts pass, YAML prints `YAML valid`, and `git diff --check` exits 0.

- [ ] **Step 5: Commit the tested fix**

```bash
git add tests/pi-aube-install-layout-contract.rb roles/common/tasks/main.yml
git commit -m "Fix macOS Pi Aube path resolution"
```

### Task 2: Verify live provisioning

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the corrected worktree playbook and the installed mise/Aube package.
- Produces: a successful provisioning run and a working direct `~/.local/bin/pi` link.

- [ ] **Step 1: Run provisioning from the worktree**

Run:

```bash
bin/provision
```

Expected: exit 0. The provision log provenance identifies the `fix-macos-pi-aube-layout` worktree and its fix commit.

- [ ] **Step 2: Verify the installed command**

Run:

```bash
test -x ~/.local/bin/pi
readlink ~/.local/bin/pi
pi --version
```

Expected: the link target ends with `/node_modules/@earendil-works/pi-coding-agent/dist/cli.js`, and Pi reports version `0.82.0`.

- [ ] **Step 3: Verify idempotence**

Run:

```bash
bin/provision
```

Expected: exit 0 with no Pi path-resolution failure.

- [ ] **Step 4: Re-run focused validation**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
ruby tests/pi-managed-aube-update-contract.rb
git status --short
```

Expected: both contracts pass, and status contains only the committed design and plan if they were not included in the implementation commit.
