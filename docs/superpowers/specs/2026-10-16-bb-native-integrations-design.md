# BB-native integration exclusions

Status: self-approved. Scope: generic NMB integrations, first slice of the BB audit retirement.

## Goal

When `BB_THREAD_ID` is nonempty after trimming, omit redundant native Pi lifecycle and browser behavior, and make Claude/Codex terminal presentation hooks no-ops. Keep standalone behavior and all safety guards. Inherited BB markers intentionally apply to descendants.

Brian also approved HNP quota/mobile/scheduling exclusions and BB continuation recovery. Those form a separate HNP slice. Do not remove continuation records or their recovery inspector, or touch the other thread's monitor implementation.

## Design

- Use the existing explicit BB marker. Do not infer root process ownership.
- Gate native ASR register/update and `done_session` independently from the rest of `managed-hooks.ts`.
- Gate Pi terminal naming publication, pane binding, task-subject generation and current-spec output for BB, including TUI descendants. Retain main/edit/commit/push/worktree/PR guards.
- Install an owned optional-package loader for the native session browser. Narrow the package's standard settings declaration to `extensions: []`, then invoke its original factory only outside BB. Do not modify third-party bytes or globally uninstall it. Package import failure must remain visible outside BB.
- Add early no-op marker gates only to the presentation shell hooks: Claude working titles, subject reminders and pane binding; Codex subject reminder and pane binding; shared current-spec tracking. Consume no payload and run no commands in BB.
- Replace the Claude statusline shell command with a managed script. In BB it exits before invoking aubx; otherwise it runs the same pinned ccstatusline command. This avoids changing shared settings per launch. The SDK may already ignore statusLine; no overhead saving is claimed without live evidence.
- Keep retained ASR/native session history unchanged. BB owns new session recovery and completion. Standalone registration and completion remain unchanged.

## Alternatives

A separate BB provider profile would omit resources before loading, but the installed provider exposes no settings. Patching its vendor bundle is rejected. Blanket package or extension removal would break standalone use and safety hooks. Owned loader factories plus the explicit marker use supported Pi package filtering without either risk.

## Verification

Run existing managed-hook suites with BB marker absent. Execute production factories with inert sinks for absent/empty/whitespace/present markers and RPC/TUI modes. Check BB has neither ASR calls nor completion/browser registrations; standalone retains them. Trigger name changes and tools to check presentation skips without losing guards. Exercise each shell hook with a BB marker and failing command stubs, then compare standalone statusline arguments with the old command. Verify actual Pi resource discovery does not load the browser twice. No retained cosmetic test is justified under NMB's material-value rule.

This is a runtime/configuration change, not a prompt rewrite. Do not rewrite tool descriptions, safety reminders or skills in this slice.

## Rollout

Open an NMB PR. After merge, provision the affected hosts through normal tooling. Fresh/reloaded provider sessions are needed. Do not deploy unmerged code or restart active BB sessions. HNP continuation handoff must be ready before its native continuation entry points are disabled.
