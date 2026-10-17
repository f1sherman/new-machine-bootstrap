# Official pstack reference snapshot

- Source: https://github.com/cursor/plugins/tree/101b274dd991f694e1f7024be2157e5f3adf07de/pstack
- Repository: `cursor/plugins`
- Commit: `101b274dd991f694e1f7024be2157e5f3adf07de`
- Retrieved: 2026-10-17
- License: MIT, preserved in `LICENSE`.
- Selected complete paths: `skills/`, `agents/`, `docs/`, `README.md`, `LICENSE`.
- Excluded: Cursor plugin registration, assets, dormant automations, and `.gitignore`.
- Content modifications: none. Executable bits are preserved.
- `SHA256SUMS` covers every selected upstream file, not this local provenance file.

This tree is reference material. It is deliberately deployed outside harness skill discovery. The local entry and portability policy live in `roles/common/files/config/skills/pstack/pstack/`.

To update, deliberately choose and review a new official commit, download its GitHub source archive, and replace only the selected complete paths above. Reject source symlinks and unsafe paths. Preserve source bytes and executable modes, regenerate SHA256SUMS over the selected files, and update this record. Do not mix snapshots or edit upstream files by hand. Review upstream agent, script, model, autonomy, and external-dependency changes before provisioning. No automatic upstream update is configured during the trial.

Verify the selected bytes from this directory with `shasum -a 256 -c SHA256SUMS`. Verify authenticity by comparing selected paths against a fresh archive of the recorded commit, not only against the local manifest.
