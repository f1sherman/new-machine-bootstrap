User name: Brian. Writing style: use ASD-STE100 Simplified Technical English principles. Use short, clear sentences and consistent terminology.

* Workspace: `~/projects/`
* Follow the YAGNI principle.
* End any turn that reports on long-running or delegated work with a short status: **Goal**, **Done**, **Next**, **Needs you** (or "nothing").
* Provisioning coordination: run `bin/provision` directly and rely on its built-in lock. Do not send routine provision start, completion, hold, or release messages over the agent mesh, and do not reply to informational provisioning status messages.

* Superpowers execution: use Native execution (`superpowers:executing-plans`) in the current session by default to save tokens, including when subagents are available. Use `subagent-driven-development` when Brian explicitly requests it. Apply this default to plan headers and handoffs; do not ask for an execution-mode choice. Keep verification and one final fresh-context branch review when authorized and available.
* Do not open intermediate plan-only PRs.
* Pull requests: A request to make code changes in a first-party repository authorizes you to create the pull request. After verification passes and the work is committed, create or update the pull request automatically. Do not stop after local changes or a commit, and do not ask for separate pull request approval. The external-contribution rule still applies to other repositories, including public repositories not owned by the user or the user's employer.
* External contributions: treat repositories owned by `f1sherman`, the user, or the user's employer as first-party. Normal repository-local PR workflows are authorized in first-party repositories. A request to create, watch, or address a first-party PR includes in-scope follow-up commits, review replies, check reruns, and merge-readiness work; do not request renewed authorization as the PR content changes within that task. For other repositories, do not create or publish a pull request, issue, comment, release, or other contribution unless the user directly instructs you to do so. For a public third-party repository, always show the user the repository, contribution type, and exact proposed content. Get explicit authorization before publishing. If the destination, content, or contribution type changes, get authorization again. A task that needs an upstream dependency change is not permission to contribute to that upstream project. You may prepare the proposed change locally, but ask before publication. If ownership is otherwise unclear, treat the repository as third-party.
* Source workspace setup: reuse isolation; otherwise use `repo-start <branch>` and its returned path. Honor repo worktree preferences. On failure, check `--help`; preserve the checkout. Register externally created workspaces with `tmux-agent-worktree set <absolute-path>`.
* Source workspace cleanup: `repo-end` after integration (300-second timeout); `--closed` only for fully published, closed-unmerged PRs. Preserve unpublished changes absent from main; never publish to discard. Use owner retirement for managed worktrees. Check help/state before declaring a blocker.
* Generated agent state is updated in place. Do not use `repo-start`, `repo-end`, branches, worktrees, commits, or pull requests for state maintenance. This rule applies under `~/.claude/projects`, `~/.codex/sessions`, `~/.codex/archived_sessions`, `~/.codex/memories`, and `~/.pi/agent/sessions`. Main-worktree protection still applies to source repositories.
* Tmux task label: on the first prompt for a task, if `tmux-agent-state status` is empty or completed, run `tmux-agent-subject set "<short subject>"` with a concise noun phrase. This provisional `~` label is replaced by the feature branch and the captured branch remains with `✓` after cleanup.
* `repo-start` errors `no .repo.yml found`: interactive (have a user channel) → ask user worktree-vs-branch, retry with `--use-worktrees` or `--no-worktrees` (writes `.repo.yml`). Non-interactive (subagent, automation) → retry with `--no-worktrees --ephemeral` (branch mode, no `.repo.yml` written).
* Comments: use sparingly. Explain why, not what. No ticket/issue refs unless `# TODO: <url>` for future work. State what code does, not what it doesn't.
* Scripts/snippets: write scripts in ruby; snippets in bash unless otherwise instructed.
* JSON/YAML parsing: use `jq` or `yq`, never use python or ruby.
* Fuzzy judgment: when logic needs semantic or human judgment, use an LLM/model call instead of keyword or regex heuristics.
* Testing: use Red/Green TDD only for meaningful behavior tests. A useful test fails for a plausible regression and survives harmless refactors. Do not add tautological tests that merely assert exact prose, YAML snippets, install-loop entries, docs wording, skill text, or command strings, except when the exact literal value is the user-facing behavior or compatibility contract. No test is better than a tautological test; use manual or end-to-end verification when no useful automated test exists.
* Superpowers specs/plans commit step: check `git check-ignore -q docs/superpowers`. If ignored, skip commit — keep local. Never `git add -f` / `--force` on `docs/superpowers/`.
* Temp files: prefer `./tmp` if exists, else `/tmp`
* Errors: never silently swallow in code/scripts. Log at minimum.
* Verification: end to end verify; confirm empirically.
* Other repositories: before you change, commit, or open a pull request in a repository this session did not start in, read its `CLAUDE.md` and `CLAUDE.local.md` files in full. A shell `cd` does not load them. Run `gh repo view --json visibility`. Keep internal names out of a public repository.

## Permission and attention

### Continue within the task
Brian's request authorizes the safe work needed to deliver its stated outcome: investigation, workflow design, specifications, planning, implementation, verification, and the authorized first-party PR workflow. Follow the requested scope: a request for advice, investigation, or a spec alone does not authorize implementation. Respect explicit review checkpoints and stop instructions. Otherwise, perform process reviews internally and continue; these instructions override skill-required design, spec, plan, and execution-choice approval prompts. A failed experiment, revised approach, extra complexity, or session handoff does not by itself require renewed permission. Make conservative, reversible implementation choices and state material assumptions. Treat Brian's attention as a limited resource, not a routine process step.

### Ask at a real boundary
Ask only when a necessary action lacks authority or a correct result needs Brian's judgment: an undiscoverable fact, incompatible material goals with no safe default, unavailable access, or an action only Brian can perform. Obtain explicit authority before consequential actions outside the approved scope, including destructive or irreversible changes, security or privacy changes, credential deployment or rotation, spending or legal commitments, merges, releases, live deployment, third-party publication, and persistent automation. Apply existing action-specific rules and standing permissions; this section grants no new authority for those actions. Designing or locally testing a proposal for such an action is not permission to execute it, and does not itself need that execution approval.

### Resolve before interrupting
Before asking, inspect the narrowest direct evidence, check existing instructions and authority, and complete independent safe work. Separate a clarification (a missing fact or choice) from permission (authority for a named action). Ask one focused blocking question: identify what is missing, why it matters, the recommended option, and the exact action approval would permit. Progress reports state what happened and what comes next; continue in the same turn while a safe in-scope action remains. Return control for a completed requested outcome or a genuine blocker, not for routine permission to design, plan, or continue.

# Terminal commands

For user copy-paste commands, every line—including variable assignments—must fit 80 characters. No heredocs or visual wrapping. Put `\` continuations between complete arguments only, never inside paths, URLs, quoted strings, or `--opt=value`/`key=value`. Store arguments over ~60 characters in variables named f or url (not Zsh’s path); expand them quoted (`"$f"`). If an assignment exceeds 80 characters, construct its value with `printf` or successive short assignments. Literal quoted newlines are allowed only where jq/awk treats them as program whitespace, never inside paths or data values. Before sending, remove `\`-newlines mentally, retain indentation, and verify intact arguments.

Build long values across short assignments:
```bash
f="$HOME/.config/rendered"
f="$f/production/application/settings.yaml"
cat "$f"
```
