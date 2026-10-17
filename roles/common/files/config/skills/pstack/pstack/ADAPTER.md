# pstack harness adapter

## Authority

Use pstack as task guidance within the current user request and local policies. Existing repository, safety, test-value, worktree, provisioning, commit, PR, and publication rules remain authoritative. The upstream autonomy defaults do not grant new authority. In particular, a workflow name does not authorize a merge, external message, deployment, deletion, credential action, or third-party contribution.

Use the existing native execution workflow unless the user authorizes delegation under the installed policy. If an upstream step requires delegation that is not authorized or available, report that step as blocked. Do not claim independent review or multi-model consensus from a single-context substitute. Do not rewrite managed skills as an automatic side effect of a broken workflow.

## References

The upstream root is `$HOME/.local/share/new-machine-bootstrap/pstack`. Resolve every upstream skill, playbook, reference, script, and agent pointer against this root or its referring file. The entry directory is not the upstream root. Files in `agents/` are prompt references, not registered agent types.

For `/name` or a bold skill reference, read `skills/<name>/SKILL.md`. For `poteto-agent` or `comment-sicko`, read `agents/<name>.md` as part of the brief for an authorized existing agent. Include this adapter and the absolute upstream poteto-mode path in that brief. Do not install agent types or packages mid-task.

## Tools and models

Use only tools present in this session and their exact schemas.

| Upstream concept | This trial |
| --- | --- |
| Read, Grep, Glob, Bash | Current file-read, search, find, and command tools. Pi uses `read`, `grep`, `find`, `bash`. |
| Task | Installed delegation interface, only within its authorization and orchestration rules. Never pass Cursor fields to it. |
| AskQuestion | Current question mechanism, or a plain question only when local policy requires user input. |
| TodoWrite | Installed checklist mechanism; otherwise a task-local plan. |
| Cursor model slug | Discover available models with the installed delegation interface. Never infer an available model from an upstream name. If the required model or model diversity is unavailable, report the limitation before that workflow. |
| Readonly worker | Use a read-only agent contract when available. The brief forbids edits; inspect actual changes before accepting results. |
| Cloud agent, resume, background execution | Use the current harness contract, including its isolation, reuse, notification, and durable-work rules. |

Claude Code can also read upstream `docs/harness/claude-code.md` for tool mapping, but this adapter and current tool schemas take precedence. Codex uses its current native tools and authorized subagent API. Pi uses its installed skill and subagent mechanisms, not shell-launched agent processes.

## Unsupported capabilities

This trial does not install `cursor-team-kit`, Cursor automations, cloud agents, Bugbot, model rules, or external MCP servers. `setup-pstack` does not configure these harnesses; explain that limitation instead of writing `.cursor` rules or changing global instructions. Discover existing authorized tools before using an integration. Access to tools does not authorize searching unrelated private history.

Use existing browser/terminal verification and PR workflows when they meet the upstream step's purpose. Name the substitution. If a required dependency, independent review, live surface, or evidence source is missing, stop that workflow and report the exact missing capability. Optional unavailable steps can be skipped with a reason. Never treat a skipped verification step as a pass.

Bundled scripts are reference material, not installation hooks. Inspect a script and its dependencies before execution; respect the task's authority and repository boundary. Use the existing PR workflow rather than upstream shipping scripts. No background process, watcher, loop, or schedule is authorized merely by loading pstack.

## Scope

Activation lasts for the explicit task. Later unrelated requests return to the default workflow. Keep pstack's quality claims labeled as trial hypotheses until actual use provides evidence.
