# pstack

[pstack](https://github.com/cursor/plugins/tree/main/pstack) is poteto's set of
engineering workflows. The managed setup provides one explicit entry in Pi,
Claude Code, and Codex. It stays installed and maintained like other tooling.
It does not replace Superpowers or change the default delivery workflow.

## Use it

Start a fresh session after provisioning, or run `/reload` in native Pi.
No pstack-specific API keys, Cursor plugin, model rule, or setup interview is
needed. Pi uses the existing pi-subagents package. Claude Code uses its built-in
agents. Both use the current session model by default.

| Harness | Example |
| --- | --- |
| Pi | `/skill:pstack how does this project's request cancellation work?` |
| Claude Code | `/pstack how does this project's request cancellation work?` |
| Codex | `$pstack how does this project's request cancellation work?` |

Put an exact upstream skill directory name first to select that skill. Without
a matching name, the entry selects poteto-mode. Without arguments, it selects
poteto-help. Examples in Pi:

```text
/skill:pstack how does link-managed-skill-tree work?
/skill:pstack why was this retry boundary designed this way?
/skill:pstack benchmark-checklist assess these before/after results
/skill:pstack blast-radius inspect this small change
/skill:pstack add pagination to this endpoint
```

The last example enters poteto-mode. There is one local command, not dozens of
new commands competing with existing skill names.

## Native agents and models

The local adapter configures every role as `inherit-parent`. Ordinary use does
not require Cursor's model names, a `.mdc` file, or a setup interview. Delegates
use the current session model unless the user selects another available model.
Separate contexts on one model are not multi-model consensus. An explicit
request for model diversity still requires distinct available models.

`how` uses one read-only explainer for a narrow question. Larger questions use
explorers followed by an explainer. Pi maps these responsibilities to discovered
native agents, such as the read-only reviewer. Claude Code and Codex use their
current native delegation interfaces. Existing session authorization and
orchestration rules apply. Delegates execute assigned roles directly rather
than recursively re-running the router.

The adapter takes precedence over repeated model defaults in upstream skills.
It also preserves repository, test-value, verification, provisioning, secrets,
and publication policies. Existing PR workflows remain in charge.

Cursor-only services are not installed. Missing optional integrations must be
reported; an essential missing capability blocks the affected step rather than
being treated as passed. The scripts in the snapshot are not installation hooks.
Inspect them and their dependencies before any authorized execution.

## Installation layout

- Entry and adapter: `roles/common/files/config/skills/pstack/pstack/`.
- Official source: `roles/common/files/vendor/pstack/`.
- Deployed reference: `~/.local/share/new-machine-bootstrap/pstack`.
- Entry links: `~/.pi/agent/skills/pstack`, `~/.claude/skills/pstack`, and
  `~/.codex/skills/pstack`.

Only the entry is discoverable. The complete upstream skills, support files,
agent briefs, documentation, and MIT license remain unchanged outside skill
discovery. The updater records source provenance, SHA256 checksums, and modes.

```bash
bin/provision --tags managed-skills
```

## Automatic updates

`tool_versions.git_commits.pstack` in `vars/tool_versions.yml` pins the official
`cursor/plugins` main branch by SHA. Upstream does not publish tags or releases.
Renovate checks that branch's digest through its `git-refs` datasource in the
existing hourly workflow. Its pstack rule regenerates the snapshot and proposes
a dependency PR containing both the new pin and the complete generated diff.

The command allowlist permits exactly `bin/update-pstack` for this dependency.
Generated changes are limited to the version file and pstack vendor tree. The
datasource has no release timestamps, so this dependency explicitly uses no
minimum release age. Normal review and merge requirements still apply; this
configuration does not enable automatic merging. Accepted updates reach machines
through normal provisioning, not by an unreviewed background pull.

To regenerate or check the pin manually:

```bash
bin/update-pstack
bin/update-pstack --check
```

The updater fetches the exact SHA, validates the selected complete paths,
rejects symlinks and unsupported entries, preserves executable modes, and
replaces the generated snapshot. Git export attributes cannot omit or rewrite
selected files. A lock serializes updater runs. A failed replacement restores
the previous snapshot. If restoration fails or the process is killed, the backup
stays beside the vendor tree and subsequent runs stop for recovery instead of
deleting it. Removed upstream files cannot linger. Check
mode detects extra, missing, modified, or executable-mode-changed files without
changing the snapshot. Local portability policy belongs in the adapter, not in
hand edits to generated upstream files.

## Feedback

A separate one-shot continuation asks Brian about usefulness after one week.
That feedback does not expire or disable the installation. Any later removal
is a separate user decision. Scheduling and feedback state do not belong in the
installed skills.
