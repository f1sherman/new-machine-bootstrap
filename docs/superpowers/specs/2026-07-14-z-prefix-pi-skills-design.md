# Z-Prefixed Pi Skills Design

## Goal

Group NMB-managed custom Pi skills under a memorable `z-` prefix so Pi autocomplete can surface them together when the exact skill name is unknown.

## Scope

Rename every repository-managed Pi skill under `roles/common/files/config/skills/pi/` by prepending `z-` to its current name. Update each skill's frontmatter `name` to match its renamed directory.

Claude and Codex skill names remain unchanged. Pi skills discovered from packages, upstream repositories, `~/.agents/skills`, or other third-party locations are outside this change.

## Source Layout

Each managed Pi skill will use the same explicit name in both its directory and frontmatter. For example:

- `roles/common/files/config/skills/pi/approve-spec/` becomes `roles/common/files/config/skills/pi/z-approve-spec/`.
- `name: approve-spec` becomes `name: z-approve-spec`.
- `roles/common/files/config/skills/pi/commit/commit.sh` becomes `roles/common/files/config/skills/pi/z-commit/commit.sh`.

Internal references to managed Pi skill paths must use the renamed locations.

## Provisioning and Migration

The existing Pi skill copy task will install the renamed source tree into `~/.pi/agent/skills/`. Before installation, provisioning will explicitly remove every old unprefixed managed Pi skill directory.

This is a one-way managed-state migration. Provisioning will not install aliases, infer legacy names, or preserve both versions. Unrelated Pi skills remain untouched.

## Validation

Update `tests/pi-shared-skills.rb` to derive each expected Pi name by removing any leading underscore from the shared Claude, Codex, or common skill name, then prepending `z-`. The test will verify:

- the managed Pi directory set exactly matches the expected `z-` names;
- every Pi skill directory and frontmatter name begins with `z-`;
- each frontmatter name equals its directory name;
- the Pi commit helper exists and is executable at `z-commit/commit.sh`;
- the Ansible cleanup list contains every old unprefixed managed Pi skill name.

## Verification

Run:

1. `ruby tests/pi-shared-skills.rb`.
2. Relevant repository tests identified during implementation.
3. `bin/provision`.
4. Inspect `~/.pi/agent/skills` to confirm NMB-managed skills exist only under `z-*` names.
5. Start or reload Pi and confirm commands such as `/skill:z-commit` and `/skill:z-spec-first` appear.

Normal Ruby, Ansible, or Pi validation failures remain visible; no fallback naming behavior is introduced.
