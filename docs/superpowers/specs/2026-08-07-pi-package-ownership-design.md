# Pi Package Ownership Consolidation Design

## Goal

Give each personal Pi package one repository owner. Pin every retained package and let Renovate propose version updates. Remove packages that no longer provide useful behavior.

## Ownership boundary

NMB owns the Pi CLI, generic Pi configuration, repository-managed skills and loose extensions, and packages that are useful on all NMB hosts.

HNP owns personal package choices for `personaldev` hosts. HNP must not move those choices into NMB because non-personal hosts can require a different package set or version.

## NMB changes

NMB will keep `pi-session-manager`. It will replace the floating `npm:pi-session-manager` source with an explicit `0.1.0` version variable and a Renovate npm annotation. Both macOS and Debian installation tasks will use the versioned source.

NMB will stop installing or forcing `@ogulcancelik/pi-codex-compaction`. It will continue to remove the retired `git:github.com/algal/pi-openai-server-compaction` entry and checkout. When NMB merges Pi settings, it will preserve the active compaction package selected by HNP instead of replacing it.

NMB will stop installing `pi-subdir-context`. Existing settings entries will remain preserved until HNP reconciles them to its versioned source.

NMB will continue to own the Renovate-managed Pi CLI pin and its generic managed files.

## HNP changes

HNP will add `pi-subdir-context` to `personal_dev_pi_packages`. The initial source will be `npm:pi-subdir-context@1.1.7`. A Renovate npm annotation will manage the version variable.

HNP will remain the sole owner of `@ogulcancelik/pi-codex-compaction` and these other retained personal packages:

- `obra/superpowers`
- `nicobailon/pi-subagents`
- `pi-codex-limit`
- `pi-web-access`
- `remote-pi`

HNP will remove `pi-intercom` and `pi-prompt-template-model` from `personal_dev_pi_packages`. Provisioning will also remove any versioned or unversioned settings entry for each retired package. It will run `pi remove` when an entry is present so the package does not remain installed or loaded.

HNP will not manage `pi-session-manager`.

## Package decisions

`pi-codex-limit` stays. It shows the active OpenAI Codex subscription limits in the Pi footer and provides the `/codex-limit` dashboard. This is useful because the configured Pi provider is `openai-codex`.

`pi-intercom` is removed. Its local session messaging and `Alt+M` interface are not used. Remote Pi provides the session mesh, and pi-subagents provides its native supervisor channel.

`pi-prompt-template-model` is removed. No managed or user prompt templates use its frontmatter or execution features. Pi-subagents provides the delegation and chain behavior that is in active use.

## Renovate behavior

NMB Renovate will update the `pi-session-manager` npm pin.

HNP Renovate will update the `pi-subdir-context` npm pin and all other retained HNP package pins through its existing Ansible annotation managers.

The compaction package will have one version pin and one Renovate owner in HNP.

## Provisioning order and convergence

The repositories must converge correctly in either order:

1. NMB provisioning preserves HNP-owned package entries and does not recreate removed packages.
2. HNP provisioning installs its exact desired sources and removes its retired package entries.

After both repositories are merged, provision NMB and then the HNP `personal-dev` role on `localhost`. Provision the `personal-dev` role on other personal development hosts through the normal HNP rollout.

## Verification

Verify the NMB syntax and package-management task behavior. Confirm that NMB no longer contains an active install or forced settings entry for `pi-subdir-context` or `pi-codex-compaction`, while it installs the versioned `pi-session-manager` source.

Verify the HNP syntax and focused `personal-dev` provisioning. Confirm that `pi list` contains the exact retained package sources and does not contain `pi-intercom` or `pi-prompt-template-model`.

Start a fresh Pi session and confirm:

- nested `AGENTS.md` context loads through `pi-subdir-context`;
- the session manager is available;
- the Codex limit footer or `/codex-limit` is available;
- pi-subagents can complete a small delegated run and use its native supervisor channel;
- no `pi-intercom` broker is started by a fresh Pi session.

No new automated test is required unless implementation reveals complex behavior with material risk that existing provisioning and end-to-end verification cannot cover.

## Non-goals

This change does not move `pi-session-manager` to HNP. It does not change the Pi CLI version, the pi-subagents version, or the package choices for non-personal hosts beyond removing NMB ownership of personal packages.
