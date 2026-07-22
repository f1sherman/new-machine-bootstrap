User name: Brian. Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

* Workspace: `~/projects/`
* Bias toward action. Only ask user when you can't do it yourself.
* Provisioning coordination: run `bin/provision` directly and rely on its built-in lock. Do not send routine provision start, completion, hold, or release messages over the agent mesh, and do not reply to informational provisioning status messages.

Provisioning history: when useful, inspect `/tmp/provision-*.log`; `ls -t /tmp/provision-*.log` lists runs newest first. Each log records its source worktree, branch, commit, repository state, invocation arguments, changed-task output, and completion status. Compare that provenance with your current worktree before deciding whether deployed state may have affected your work. Do not assume unexpected deployed state is a source-code regression.
* Spec approval and plan execution: the written spec is the only approval gate; once approved, proceed without another implementation approval prompt and always choose subagent execution automatically.
* Pull requests: when verification passes and work is complete, invoke `create-pull-request` automatically; do not ask for approval to create the PR.
* Branch/worktree lifecycle: start with `repo-start <branch>`. Created other way: run `tmux-agent-worktree set <absolute-path>`. After the PR has merged, run `repo-end` with a 300s Bash timeout (`timeout: 300000`) — its post-merge cleanup and hooks can run past the default.
* Tmux task label: on the first prompt for a task, if `tmux-agent-state status` is empty or completed, run `tmux-agent-subject set "<short subject>"` with a concise noun phrase. This provisional `~` label is replaced by the feature branch and the captured branch remains with `✓` after cleanup.
* `repo-start` errors `no .repo.yml found`: interactive (have a user channel) → ask user worktree-vs-branch, retry with `--use-worktrees` or `--no-worktrees` (writes `.repo.yml`). Non-interactive (subagent, automation) → retry with `--no-worktrees --ephemeral` (branch mode, no `.repo.yml` written).
* Comments: use sparingly. Explain why, not what. No ticket/issue refs unless `# TODO: <url>` for future work. State what code does, not what it doesn't.
* Scripts/snippets: write scripts in ruby; snippets in bash unless otherwise instructed.
* JSON/YAML parsing: use `jq` or `yq`, never use python or ruby.
* Fuzzy judgment: when logic needs semantic or human judgment, use an LLM/model call instead of keyword or regex heuristics.
* Multi-line commands: write script to `/tmp`. Do not ask user to copy/paste over multiple lines.
* Testing: use Red/Green TDD only for meaningful behavior tests. A useful test fails for a plausible regression and survives harmless refactors. Do not add tautological tests that merely assert exact prose, YAML snippets, install-loop entries, docs wording, skill text, or command strings, except when the exact literal value is the user-facing behavior or compatibility contract. No test is better than a tautological test; use manual or end-to-end verification when no useful automated test exists.
* Superpowers specs/plans commit step: check `git check-ignore -q docs/superpowers`. If ignored, skip commit — keep local. Never `git add -f` / `--force` on `docs/superpowers/`.
* Temp files: prefer `./tmp` if exists, else `/tmp`
* Errors: never silently swallow in code/scripts. Log at minimum.
* Verification: end to end verify; confirm empirically.
