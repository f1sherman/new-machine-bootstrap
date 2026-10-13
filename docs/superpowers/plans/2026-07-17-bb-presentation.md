# NMB BB presentation exclusions

Authority: approved HNP combined plan `2026-07-17-bb-presentation.md` and BB customization audit; assessments are advisory. This isolated NMB worktree is the sole writing lane. Parent owns review, integration, publication, and deployment.

## Bounded specification

Use Pi's documented `ctx.mode === "tui"` gate for terminal-only effects, not `hasUI`, inherited BB variables, or inferred root ownership. Keep existing TTY/tmux/Herdr checks for TUI sessions. Restrict Pi attention BEL/UI wrapping, spec-shortcut execution, session-start pane binding/label refresh, session-name terminal publication/clearing (including Herdr), and current-spec tracking to TUI mode. This also suppresses those effects in non-BB RPC/print sessions; standalone TUI remains unchanged, including a TUI child inheriting BB variables.

Leave automatic session naming, `set_session_name`, subject generation/reminder prompts, all Claude/Codex hooks, global Pi packages/session browser, and Claude statusline unchanged. They require root/profile design or prompt-behavior evaluation. Do not split managed-hooks, change guidance/safety/ASR/completion/recovery/mesh/staleness, modify vendors or deployed state, provision, push, or create PRs.

## Implementation and verification

1. Read AGENTS.md, applicable testing policy/designs, approved plan/audit, production seams, and installed Pi API docs. NMB has no separate runbooks/testing.md; AGENTS.md is the testing authority.
2. Commit this document with z-commit's commit script directly; child delegation is prohibited. No ignored docs are force-added.
3. Make narrow mode gates in the three Pi extensions. Add `mode: "tui"` to the existing managed-hooks fixture for accurate ExtensionContext; no new automated tests.
4. Execute production extensions with inert exec/UI/output sinks across RPC+BB+TMUX+TTY, RPC without BB, standalone TUI, inherited-BB TUI, print, and non-TTY TUI. Check native naming tools, ASR registration/update, completion identity, and safety blockers survive. Record exact commands/output and limitations in ignored repo-local evidence.
5. Run focused existing checks and syntax/diff checks; retain no source-grep tests. Export source-only patch and plan patch for parent capture. Source edits remain uncommitted and nothing remains staged.

## Durable design queue (owner: Brian / parent BB thread)

- NMB-BB-ROOT: What authoritative non-inherited root capability/configuration identifies BB-owned providers? Without it retain auto naming/tool, Claude activity and pane/spec hooks, and Herdr TUI descendants. Alternatives: retain current gates; documented BB-owned capability; supported provider-specific profile. No invented launch wrapper.
- NMB-BB-SUBJECT: Are subject-generation/reminder instructions to be suppressed only for BB roots? Requires the root decision and matched behavior evals/ablation before changing prompt behavior. Retain current subject path and independent main-branch safety reminder.
- NMB-BB-PROFILE: What supported per-launch Pi package/resource and Claude settings boundary excludes native session browser/statusline without global uninstall? Keep standalone installation. Mode gating shortcut execution does not omit registration/loading.

Acceptance: independent reviewer inspects actual bytes and inert behavioral evidence; fresh live BB/provider/terminal verification remains a parent deployment step, not claimed by this worker.
