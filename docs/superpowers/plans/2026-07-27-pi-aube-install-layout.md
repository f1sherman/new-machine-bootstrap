# Pi Aube Install Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make provisioning resolve managed Pi from the current Aube-backed mise npm layout.

**Architecture:** Derive one mise install root, then address the package through `node_modules/@earendil-works/pi-coding-agent` and the command through `node_modules/.bin/pi`. A contract test locks those paths and rejects the removed legacy path.

**Tech Stack:** Ansible YAML, Bash, Ruby contract tests

## Global Constraints

- Public artifacts must contain no private organization, repository, ticket, employee, DevPod, or Codespaces references.
- Support only the current managed Aube layout; do not add legacy layout fallback.
- Missing managed paths remain fatal.

---

### Task 1: Lock and implement the current Aube paths

**Files:**
- Create: `tests/pi-aube-install-layout-contract.rb`
- Modify: `roles/common/tasks/main.yml:1399-1447`

**Interfaces:**
- Consumes: `mise where npm:@earendil-works/pi-coding-agent`, returning the managed install root.
- Produces: package link source `<root>/node_modules/@earendil-works/pi-coding-agent`; command source `<root>/node_modules/.bin/pi`.

- [ ] **Step 1: Write the failing contract test**

Create a Ruby test that reads `roles/common/tasks/main.yml`, asserts both current path fragments occur, and rejects `npm:@earendil-works/pi-coding-agent')/bin/pi`.

```ruby
# frozen_string_literal: true

repo_root = File.expand_path('..', __dir__)
tasks = File.read(File.join(repo_root, 'roles/common/tasks/main.yml'))
current_package = 'node_modules/@earendil-works/pi-coding-agent'
current_bin = 'node_modules/.bin/pi'
legacy_bin = %q{npm:@earendil-works/pi-coding-agent')/bin/pi}

abort "missing current Pi package path: #{current_package}" unless tasks.include?(current_package)
abort "missing current Pi executable path: #{current_bin}" unless tasks.include?(current_bin)
abort "legacy Pi executable path remains: #{legacy_bin}" if tasks.include?(legacy_bin)

puts 'Pi Aube install layout contract passed'
```

- [ ] **Step 2: Verify RED**

Run: `ruby tests/pi-aube-install-layout-contract.rb`
Expected: FAIL with `missing current Pi executable path: node_modules/.bin/pi`.

- [ ] **Step 3: Implement the explicit current paths**

In the package-link task, replace executable inference with:

```bash
pi_root="$("{{ mise_bin }}" where 'npm:@earendil-works/pi-coding-agent')"
export PI_PACKAGE_ROOT="$pi_root/node_modules/@earendil-works/pi-coding-agent"
```

In Ruby, resolve `PI_PACKAGE_ROOT` directly and remove `pi_bin` inference:

```ruby
package_root = Pathname.new(ENV.fetch("PI_PACKAGE_ROOT")).realpath
```

In the local-bin task, use:

```bash
pi_bin="$("{{ mise_bin }}" where 'npm:@earendil-works/pi-coding-agent')/node_modules/.bin/pi"
```

- [ ] **Step 4: Verify GREEN and syntax**

Run:

```bash
ruby tests/pi-aube-install-layout-contract.rb
ruby -e 'require "yaml"; YAML.load_file("roles/common/tasks/main.yml"); puts "YAML valid"'
ruby tests/pi-managed-aube-update-contract.rb
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit implementation**

```bash
git add tests/pi-aube-install-layout-contract.rb roles/common/tasks/main.yml
git commit -m "Fix managed Pi paths for current Aube layout"
```

### Task 2: Verify provisioning behavior

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the updated Ansible tasks.
- Produces: a valid `~/.local/bin/pi` and active package link after provisioning.

- [ ] **Step 1: Run repository verification**

Run: `bin/provision`
Expected: exit 0 with a new `/tmp/provision-*.log` whose provenance identifies this worktree.

- [ ] **Step 2: Verify installed command**

Run:

```bash
test -x ~/.local/bin/pi
readlink ~/.local/bin/pi
pi --version
```

Expected: the link target contains `node_modules/.bin/pi`; Pi reports the managed version.

- [ ] **Step 3: Re-run the focused contract**

Run: `ruby tests/pi-aube-install-layout-contract.rb`
Expected: PASS.
