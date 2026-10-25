# pstack harness adapter

## Authority

Use pstack as task guidance within the current user request and local policies. Existing repository, safety, test-value, worktree, provisioning, commit, PR, and publication rules remain authoritative. The upstream autonomy defaults do not grant new authority. In particular, a workflow name does not authorize a merge, external message, deployment, deletion, credential action, or third-party contribution.

Keep native execution for ordinary implementation steps. For a user-invoked pstack workflow, use its required delegates through the installed interface when the current request and session policy permit delegation. For `how`, a narrow question needs one read-only explainer; do not replace that explainer with the parent's own answer. If delegation is not permitted or available, report that specific limitation. Do not rewrite managed skills as an automatic side effect of a broken workflow.

## References

The upstream root is `$HOME/.local/share/new-machine-bootstrap/pstack`. Resolve root-qualified paths such as `skills/how/SKILL.md` from this root. Resolve relative links from the file containing them. In particular, poteto-mode's `playbooks/<name>.md` means `$HOME/.local/share/new-machine-bootstrap/pstack/skills/poteto-mode/playbooks/<name>.md`, not a top-level `playbooks/` directory. The entry directory is not the upstream root. Files in `agents/` are prompt references, not registered agent types.

For `/name` or a bold skill reference, read `skills/<name>/SKILL.md`. For `poteto-agent` or `comment-sicko`, read `agents/<name>.md` as part of the brief for an authorized existing agent. Include this adapter and the absolute upstream poteto-mode path in that brief. Do not install agent types or packages mid-task.

## Tools and models

Use only tools present in this session and their exact schemas.

### Model setup

For `setup-pstack`, read [MODEL-SETUP.md](MODEL-SETUP.md) and use its native discovery, budget, recommendation, confirmation and save procedure instead of upstream Cursor rule-writing. Choices are machine-local and harness-specific; no model IDs or catalogs are installed in the skills.

### Model dispatch

At the start of each pstack task, identify the harness (`pi` or `claude-code`) and run `ruby <adapter-directory>/models.rb show <harness>`. This reads user-owned runtime state at `$HOME/.local/state/pstack/models/<harness>.json`. The helper rejects copied-host, malformed or unsafe profiles. A failed read blocks model selection rather than resetting the profile. Other harnesses use inheritance and report persistent setup as unsupported.

Precedence is an explicit user model choice, then the saved role selection, then `inherit-parent` for an unconfigured or omitted role. This overrides all upstream Cursor model defaults, including repeated defaults in routed skills. Never import a catalog or profile from another machine or harness.

Before each delegate launch, discover the current native model catalog. In Pi, use the installed subagent model catalog and exact provider/id; CLI listings alone cannot override the current session registry. If that catalog is truncated (it ends with an "and N more" line) and a configured model is not among the listed entries, look up that exact provider/id with `pi --list-models <provider/id>`. A matching row counts as catalog evidence for that model, because the CLI reads the same registry. No match still blocks the role. In Claude, use the native Agent/Task model schema and the current session's available choices; do not guess entitlement from CLI help. Normalize fresh catalog evidence to the JSON shape in MODEL-SETUP.md. Run `ruby <adapter-directory>/models.rb resolve <harness> <exact-role> <catalog-file>` for the role being launched. A configured but unavailable model or effort blocks that role and requests setup; do not silently inherit or substitute. An explicit user override may replace that role after current availability validation, without changing the saved profile.

Use each returned selection for one delegate. For Pi, pass the exact model override and, only when resolved, its `:<thinking>` suffix. For Claude, pass the accepted native model value; never pass Pi provider IDs or thinking suffixes to Agent/Task. For `inherit-parent` or `auto`, omit both overrides and choose an inheriting native agent profile. For a real configured model, explicitly override any agent-pinned model. Panel list length controls delegate count, not permission to exceed current orchestration limits. Arena's cross-judge pool remains a candidate pool; choose one suitable entry as upstream specifies. The parent chat model stays unchanged.

The local setup guide owns profile schema, budget handling and confirmation. Do not rerun setup or change saved choices merely because a normal task encounters a stale model.

Separate agents provide separate contexts, not model diversity. When a panel uses the same model, state that fact and never claim multi-model consensus. If the user explicitly requires distinct models, discover available choices and report a blocker only if that requirement cannot be met.

For Pi, discover native agents and use a read-only agent such as `reviewer` for `how` explorers and explainers. A role name in an upstream skill is a prompt responsibility, not a required installed agent name. For a narrow `how` task, fill `references/explainer-prompt.md` without explorer findings and give the chosen agent the question, repository path, this adapter, and read-only scope. Follow the installed orchestration rules for multiple delegates. A parent's delegated brief already assigns the role: an explainer executes it directly rather than recursively spawning another explainer.

| Upstream concept | Native mapping |
| --- | --- |
| Read, Grep, Glob, Bash | Current file-read, search, find, and command tools. Pi uses `read`, `grep`, `find`, `bash`. |
| Task | Installed delegation interface, only within its authorization and orchestration rules. Never pass Cursor fields to it. |
| AskQuestion | Current question mechanism, or a plain question only when local policy requires user input. |
| TodoWrite | Installed checklist mechanism; otherwise a task-local plan. |
| Cursor model slug | Use the validated local role mapping above. Resolve explicit user overrides through fresh model discovery; never forward an upstream slug blindly. |
| Readonly worker | Use a read-only agent contract when available. The brief forbids edits; inspect actual changes before accepting results. |
| Cloud agent, resume, background execution | Use the current harness contract, including its isolation, reuse, notification, and durable-work rules. |

For Claude Code, map read-only roles to the built-in `Explore` agent and poteto-agent/comment-sicko responsibilities to the built-in `general-purpose` agent with the upstream brief. Use the current native Agent/Task schema. Pass the resolved model for a configured role. For an inheritance alias, omit the model and verify that the chosen profile inherits: a custom agent can pin a different model even when the call omits `model`. The plugin-specific `pstack:poteto-agent` and `pstack:comment-sicko` agent types are not installed.

Claude Code can also read upstream `docs/harness/claude-code.md` for other tool mapping, but this adapter and current tool schemas take precedence. Codex uses its current native tools and authorized subagent API. Pi uses its installed skill and subagent mechanisms, not shell-launched agent processes.

## Unsupported capabilities

This integration does not install `cursor-team-kit`, Cursor automations, cloud agents, Bugbot, or external MCP servers. `setup-pstack` configures only the machine-local native profiles described in MODEL-SETUP.md; it does not write `.cursor` rules or change global instructions. Discover existing authorized tools before using an integration. Access to tools does not authorize searching unrelated private history.

Use existing browser/terminal verification and PR workflows when they meet the upstream step's purpose. Name the substitution. If a required dependency, independent review, live surface, or evidence source is missing, stop that workflow and report the exact missing capability. Optional unavailable steps can be skipped with a reason. Never treat a skipped verification step as a pass.

Bundled scripts are reference material, not installation hooks. Inspect a script and its dependencies before execution; respect the task's authority and repository boundary. Use the existing PR workflow rather than upstream shipping scripts. No background process, watcher, loop, or schedule is authorized merely by loading pstack.

## Scope

Activation lasts for the explicit task. Later unrelated requests return to the default workflow. Report only outcomes supported by actual execution evidence.
