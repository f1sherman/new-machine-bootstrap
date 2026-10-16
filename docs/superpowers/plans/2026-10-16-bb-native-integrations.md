# BB native integration exclusions implementation plan

> Execution: Native `superpowers:executing-plans` in the current session. Self-approved. Final fresh-context review is owned by the PR workflow.

**Goal:** Disable generic native presentation and ASR lifecycle in BB without changing standalone or safety behavior.
**Architecture:** Explicit BB marker gates, an owned optional-package factory, and a statusline script. Standard Pi package filtering prevents duplicate browser loading.
**Tech stack:** TypeScript, Bash, Ansible.
**Spec:** `docs/superpowers/specs/2026-10-16-bb-native-integrations-design.md`.

## Constraints and review focus

No vendor edits, record deletion, prompt rewrites, monitor changes or deployment before merge. Empty and whitespace markers retain standalone behavior. Test RPC and TUI descendants. Keep ASR history and every safety handler. Browser absence outside BB must fail visibly rather than silently disappear.

## Tasks

- [x] Run `env -u BB_THREAD_ID bash tests/pi-managed-hooks.sh` and `env -u BB_THREAD_ID bash tests/pi-agent-state-managed-hooks.sh` as baseline.
- [x] Update `roles/common/files/pi/extensions/managed-hooks.ts`: gate registry registration/update, completion registration, terminal publication, pane binding, task-subject generation and current-spec paths with the captured marker. Keep all Git policy paths unchanged.
- [x] Add early marker gates to presentation hooks in `roles/common/files/claude/hooks/` and `roles/common/files/bin/`; add and deploy `claude-statusline` with unchanged standalone command.
- [x] Create `pi/extensions/native-session-browser.ts` using a supported extension factory import. Update `tasks/main.yml` and its Pi settings reconciliation to disable direct package loading, retaining the installed package.
- [x] Execute a temporary production-artifact probe for lifecycle, marker and browser-loading cases, plus shell no-op checks. Use actual Pi loading where import semantics need verification; no model requests or live record mutations.
- [x] Re-run both existing suites and syntax/diff checks. Record the exact evidence and limitations below.
- [x] Commit implementation; run PR workflow review, resolve material findings and open PR (#668).

## Evidence

Bell and spec-shortcut factories also return before registration in BB, including TUI descendants; a production-factory probe checked both marker states. Both existing suites passed before and after implementation. An eight-case production lifecycle probe confirmed no completion tool or ASR register/update calls in BB RPC/TUI, preserved standalone behavior for absent/empty/whitespace markers, and retained main-push blocking in every case. Pi's actual extension loader registered zero browser commands in BB and exactly `sessions`/`sall` outside BB. Seven shell hooks exited silently in BB with malformed input and unavailable commands. Three statusline cases preserved the standalone pinned command and skipped it in BB. Ansible executed the production settings task file against temporary state and preserved unrelated package fields while disabling direct browser loading for string and object entries. YAML parse and diff checks passed. These are inert-boundary checks, not live Claude/Codex UI or deployed-provider proof. No model inference or token saving was measured.
