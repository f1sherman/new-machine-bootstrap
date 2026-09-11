# Stop Slop Skill Installation Design

## Goal

Install the upstream Stop Slop writing skill for Claude Code, Codex, and Pi.
Provision the same pinned content on macOS and Debian hosts.

## Assumptions

- “codec” means Codex CLI.
- “cloud code” means Claude Code.
- The installed names are `_stop-slop` for Claude Code and Codex, and
  `z-stop-slop` for Pi.
- The repository will vendor upstream commit
  `8da1f030185bdfe8471220585162991eaeb970e9`.
- Future upstream updates require an explicit repository change.

## Existing Structure

The common role copies `roles/common/files/config/skills/common/` to both
`~/.claude/skills/` and `~/.codex/skills/`. It copies
`roles/common/files/config/skills/pi/` to `~/.pi/agent/skills/`. This structure
supports the requested agent-specific names without new Ansible tasks.

## Approaches Considered

### Use one shared source and add custom copy tasks

This approach avoids duplicate content. It adds Ansible logic to rename the
skill and rewrite its metadata for each destination. The extra provisioning
logic has more maintenance cost than the small duplicated skill tree.

### Fetch upstream during provisioning

This approach gets upstream changes without a repository update. It makes
provisioning depend on GitHub availability and permits unreviewed changes. It
also makes installed content less reproducible.

### Vendor agent-specific copies

This approach puts `_stop-slop` in the shared Claude Code and Codex source and
`z-stop-slop` in the Pi source. It follows the existing copy model and requires
no task changes. This is the selected approach.

## File Layout

Create these two skill trees:

- `roles/common/files/config/skills/common/_stop-slop/`
- `roles/common/files/config/skills/pi/z-stop-slop/`

Each tree contains:

- `SKILL.md`
- `README.md`
- `LICENSE`
- `UPSTREAM.md`
- `references/examples.md`
- `references/phrases.md`
- `references/structures.md`

The vendored instructions and references match upstream commit `8da1f030`.
Only the `name` field in each `SKILL.md` changes to match the installed agent
name. `UPSTREAM.md` records the repository URL, full commit, author, license,
and local metadata change.

## Attribution and License

Keep Hardik Pandya’s author metadata in each `SKILL.md`. Include the complete
upstream MIT license and README in both vendored trees. Record the source URL
and pinned commit in `UPSTREAM.md` so users can trace the copied work.

## Installation

Existing Ansible copy tasks install the trees at:

- `~/.claude/skills/_stop-slop`
- `~/.codex/skills/_stop-slop`
- `~/.pi/agent/skills/z-stop-slop`

Provisioning remains offline for these files and idempotent.

## Verification

Do not add a narrow automated test for static copied files. Such a test would
repeat Ansible configuration and would not provide unique regression
protection. Run `bin/provision`, compare each deployed tree with its repository
source, and check each deployed `SKILL.md` name. Run `bin/provision --check` to
validate dry-run compatibility. Recursive Ansible copy tasks can report changes
in check mode even when deployed file content and modes match their sources.
