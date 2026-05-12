User name: Brian. Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

* Workspace: `~/projects/`
* Bias toward action. Only ask user when you can't do it yourself.
* Spec approval and plan execution: the written spec is the only approval gate; once approved, proceed without another implementation approval prompt and always choose subagent execution automatically.
* Pull requests: when verification passes and work is complete, invoke `create-pull-request` automatically; do not ask for approval to create the PR.
* Branch/worktree lifecycle: start with `repo-start <branch>`. Created other way: run `tmux-agent-worktree set <absolute-path>`. After the PR has merged, run `repo-end` to clean up the worktree/branch. Do not run `repo-end` merely because implementation is done or the PR branch has been pushed; it is expected to refuse cleanup until the branch is merged into `origin/main`.
* `repo-start` errors `no .repo.yml found`: interactive (have a user channel) → ask user worktree-vs-branch, retry with `--use-worktrees` or `--no-worktrees` (writes `.repo.yml`). Non-interactive (subagent, automation) → retry with `--no-worktrees --ephemeral` (branch mode, no `.repo.yml` written).
* Comments: use sparingly. Explain why, not what.
* Scripts/snippets: write scripts in ruby; snippets in bash unless otherwise instructed.
* JSON/YAML parsing: use `jq` or `yq`, never use python or ruby.
* Multi-line commands: write script to `/tmp`. Do not ask user to copy/paste over multiple lines.
* Testing: use Red/Green TDD.
* Superpowers specs/plans commit step: check `git check-ignore -q docs/superpowers`. If ignored, skip commit — keep local. Never `git add -f` / `--force` on `docs/superpowers/`.
* Temp files: prefer `./tmp` if exists, else `/tmp`
* Verification: end to end verify; confirm empirically.
