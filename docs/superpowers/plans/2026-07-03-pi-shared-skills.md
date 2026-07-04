# Pi Shared Skills Provisioning Plan

## Goal

Provision Pi with source-managed copies of every generic personal skill that new-machine-bootstrap already provisions for Claude or Codex, using Pi-valid skill names and Pi-specific helper paths.

## Design

- Keep existing Claude and Codex skill source trees unchanged.
- Add `roles/common/files/config/skills/pi/` as the Pi-specific shared skill source tree.
- Pi skill directory names and frontmatter names strip leading underscores because Pi rejects underscore-prefixed skill names.
- Install Pi shared skills to `~/.pi/agent/skills/` from the common role.
- Keep repo-specific PR workflow skills out of NMB; home-network-provisioning continues to own those.

## Tasks

- [x] Copy/adapt existing HNP Pi shared skill copies into NMB.
- [x] Add missing Pi counterparts for NMB's Codex/Claude-only session conversion skills.
- [x] Wire common role provisioning to create `~/.pi/agent/skills` and copy the Pi tree.
- [x] Add a contract test that Pi skills mirror NMB's Claude/Codex/common skill counterparts and use Pi-valid names.
- [x] Run targeted verification.

## Verification

- `ruby tests/pi-shared-skills.rb`
- `ansible-playbook --syntax-check playbook.yml`
