# Native pstack model setup

This replaces upstream setup-pstack's Cursor rule-writing steps. Keep the adapter's authority boundaries. Setup recommends choices; it does not prove a universal best model.

## Discover on this machine

1. Identify the active harness: `pi` or `claude-code`. Other harnesses report that persistent setup is unsupported here; keep inheritance, rather than reuse another harness's profile.
2. Read current state with `ruby <adapter-directory>/models.rb show <harness>` and read the current role labels with `ruby <adapter-directory>/models.rb roles`. A failed state read needs repair or an explicit user decision, not an overwrite.
3. Discover models through this session's actual delegation interface. In Pi, enable/discover the installed subagent tools and use their model catalog, then their native agent capability listing. `pi --list-models` is supplemental CLI evidence, not permission to use a model missing from the current session registry. In Claude Code, inspect the native Agent/Task model parameter and any current session model catalog. Confirm exact accepted aliases or IDs, including any custom agent model overrides. A CLI help example is not proof of access. Never infer access from models configured on another machine, a provider login, a model family name, upstream defaults, or a cached catalog.
4. If the session exposes no dependable model catalog, say exactly what is missing. Ask the user for the currently available choices or use an explicitly chosen inherit-parent mapping; do not fabricate a list. Catalog membership is not proof of successful authentication or service entitlement. Report any later denial and request a new choice.

Build a task-local catalog JSON file from that fresh evidence. Shape: `[{"model":"<exact native choice>","thinking":[]}]`. Include only current choices. `inherit-parent` and `auto` are always supported aliases and need not be in the catalog. Include a thinking level only if both the current harness schema and the model's discovered capabilities confirm it. An empty thinking list means no per-delegate effort override is known. Native Claude Agent/Task does not expose Pi's thinking suffix: keep its lists empty. Never read or export credentials to build a catalog.

## Recommend and confirm

Ask for the budget using the upstream options:

- `unlimited — max reasoning`
- `large — xhigh reasoning`
- `medium — high reasoning`
- `small — medium reasoning`

Name the saved budget if present. With no profile, explain that large matches upstream intent, not a confirmed local model choice. An explicit budget in the current request answers this question; otherwise wait for the user's answer before choosing or saving a budget. Do not run paid model probes as part of discovery.

After the budget answer, propose every role returned by `roles`. Preserve existing confirmed choices on a re-run when they remain available. Use current model descriptions/capabilities to recommend fast coding/exploration models for worker roles and stronger reasoning/prose models for judgment, synthesis and hard tasks. For panels, start with the upstream two-entry lists on first setup; preserve confirmed list lengths on re-runs. Recommend distinct suitable models where actually available, preserving one delegate per list entry. If only one model is suitable, repeat it in both entries and state that the contexts are independent but the model is the same. Change panel size only when the user explicitly requests that change. Explain speed, quality, cost and unknowns. Model names alone do not establish quality or price; mark uncertain rankings as recommendations, not measured facts. With one suitable model, use it honestly rather than invent diversity.

The budget is a target. For a real Pi choice, select the highest confirmed supported thinking level at or below its target; omit thinking if it is not exposed and disclose the limit. In Claude, budget informs model selection but cannot force unsupported per-delegate reasoning controls. `inherit-parent` and `auto` omit both model and thinking overrides. Ask the user to accept the complete table or change roles. This step is required even if the request simply says to run setup. If the current request already approves an exact complete table and budget, use that approval. A role selection never changes the parent chat model.

## Save only local runtime state

After confirmation, write a task-local profile JSON file:

```json
{
  "version": 1,
  "budget": "large",
  "roles": {
    "how explorer": [{"model": "<confirmed native choice>"}],
    "how explainer": [{"model": "<confirmed native choice>"}]
  }
}
```

Populate the full confirmed table, not just this abbreviated shape. Each role is an array. Non-panel roles have exactly one entry; panel entries retain their count. An optional `thinking` field is a separately confirmed native level, not part of the stored model ID.

Re-check the catalog immediately before saving, then run `ruby <adapter-directory>/models.rb save <harness> <profile-file> <catalog-file>`. Require success and read `show` back. The helper adds the current hostname and harness, validates the choices, and atomically writes a private profile at `$HOME/.local/state/pstack/models/<harness>.json`. These profiles are user-owned runtime state, not provisioned configuration. Do not add their contents to a repository, copy them to another host, or modify global harness settings or Cursor rules. Provisioning updates the helper and guidance but never resets these choices.

Report the machine, harness, saved budget, selected models, unsupported effort controls, and that subsequent pstack tasks read the profile. No restart is required for the profile itself. Remove only this invocation's temporary proposal/catalog files when done. A stale or copied-host profile requires setup on the current machine; do not repair it by silently selecting another model.
