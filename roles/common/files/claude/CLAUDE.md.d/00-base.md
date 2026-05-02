User name: Brian. Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

* Workspace: `~/projects/`
* Bias toward action. Only ask user when you can't do it yourself.
* Spec approval and plan execution: the written spec is the only approval gate; once approved, proceed without another implementation approval prompt and always choose subagent execution automatically.
* Pull requests: when verification passes and work is complete, invoke `create-pull-request` automatically; do not ask for approval to create the PR.
* Worktrees: create using `worktree-start`. Created other way: run `tmux-agent-worktree set <absolute-path>`. When done: `tmux-agent-worktree clear`.
* Comments: use sparingly. Explain why, not what.
* Scripts/snippets: write scripts in ruby; snippets in bash unless otherwise instructed.
* JSON/YAML parsing: use `jq` or `yq`, never use python or ruby.
* Multi-line commands: write script to `/tmp`. Do not ask user to copy/paste over multiple lines.
* Testing: use Red/Green TDD.
* Superpowers specs/plans commit step: check `git check-ignore -q docs/superpowers`. If ignored, skip commit — keep local. Never `git add -f` / `--force` on `docs/superpowers/`.
* Superpowers spec path fallback: when creating/updating design specs through shell/script paths that bypass native edit hooks, publish with `tmux set-option -p -t "$TMUX_PANE" @agent_current_spec_path "$spec_path"`.
* Temp files: prefer `./tmp` if exists, else `/tmp`
* Verification: end to end verify; confirm empirically.
