---
name: z-suggest-goal
description: Suggest a pasteable /goal command from the current session.
disable-model-invocation: true
---

# Suggest a session goal

Draft a goal for Brian to review and paste. Do not start, replace, or update a goal, call goal tools, or carry out the proposed work.

## Select the remaining work

Use the conversation and any arguments to identify the current user-approved task, completed work, remaining work, and constraints. Inspect relevant files or PR state only when needed to resolve uncertainty. Keep the goal within the authorized scope. If the task is complete, say no goal is needed. If two incompatible objectives remain, ask one focused question instead of guessing.

## Draft the command

Write one self-contained `/goal` command. Name the desired outcome, concrete completion evidence, scope and constraints, how to choose the next action between attempts, and when to stop as blocked with evidence and the input needed. Use verified commands and paths; do not invent them. Preserve approval gates. Include a token budget only if Brian requested one.

For multi-step work, include a persistent Markdown progress checklist in the proposed goal. Reuse the task's existing plan; otherwise use a new file under `docs/superpowers/goals/`, subject to repository rules. Tell the executing agent to update it after each verified step, with completed checkboxes, evidence, blockers, and the next action. Draft these instructions only; do not create or change the file now.

## Return the suggestion

Return one fenced `text` block containing the complete command on one logical line. Keep it concise enough to review. Include `/goal` so Brian can paste the whole block without adding a prefix. Omit alternatives, rationale, and follow-up offers unless Brian asks for them.
