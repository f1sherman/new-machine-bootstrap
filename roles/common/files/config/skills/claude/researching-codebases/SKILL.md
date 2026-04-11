---
name: personal:research-codebase
description: >
  Conduct comprehensive codebase research by spawning parallel sub-agents and generating documentation.
  Use when the user asks how the current system works or requests a codebase deep dive.
---

# Research Codebase

Document the codebase as it exists now. Use parallel sub-agents. Synthesize evidence. Write research docs.

## Boundary

- Document only.
- No critique.
- No recommendations.
- No root cause analysis unless the user asks.
- No future changes unless the user asks.
- No refactoring, optimization, or architecture advice.
- Describe what exists, where it exists, how it works, and how parts connect.

## Start

If the user has not given a research question, reply with:

```text
I'm ready to research the codebase. Please provide your research question or area of interest, and I'll analyze it thoroughly by exploring relevant components and connections.
```

Then wait.

## Workflow

1. Read mentioned files first.
   - If the user names files, docs, JSON, or accessible tickets, read them fully before anything else.
   - Use the Read tool with no limit or offset.
   - Read them in main context before spawning sub-tasks.

2. Decompose the question.
   - Split the request into research areas.
   - Think through the patterns, connections, and structure the user is likely asking about.
   - Identify relevant components, files, and directories.
   - Create a TodoWrite plan for the subtasks.

3. Spawn parallel sub-agents.
   - Use Task agents for concurrent research.
   - Keep prompts focused on read-only documentation.
   - Use these agents when they are available and appropriate:
     - `personal:codebase-locator` to find where files and components live.
     - `personal:codebase-analyzer` to explain how specific code works.
     - `personal:codebase-pattern-finder` to find existing patterns and examples.
     - `personal:web-search-researcher` only if the user explicitly asks for web research.
   - If web research is used, tell the agent to return links and include them in the final report.
   - Start with locator work, then analyze the most useful findings.
   - Run multiple agents in parallel when they search different areas.
   - Remind every agent it is documenting, not evaluating.

4. Wait for every sub-agent.
   - Wait for all sub-agent tasks to finish before synthesis.
   - Compile all results together.
   - Treat live codebase findings as primary source of truth.
   - Read the key source files and line references yourself before finalizing the report.
   - Connect findings across components.
   - Include file paths and line numbers.
   - Verify paths.
   - Answer the user with concrete evidence.

5. Gather metadata before writing.
   - Run `~/.local/bin/spec-metadata`.
   - If `spec-metadata` is unavailable or incomplete, derive the missing metadata from git, the repo, and the current date/time. Do not invent values.
   - Build the filename as `.coding-agent/research/YYYY-MM-DD-ENG-XXXX-description.md`.
   - Use `YYYY-MM-DD` for today.
   - Include `ENG-XXXX` only when there is a ticket.
   - Use a brief kebab-case description.
   - Examples:
     - `2025-01-08-ENG-1478-parent-child-tracking.md`
     - `2025-01-08-authentication-flow.md`

6. Write the research document.
   - Use the metadata from step 5.
   - Start with YAML frontmatter.
   - Keep frontmatter consistent across research docs.
   - Use snake_case for multi-word fields.
   - Keep tags relevant to the topic and components studied.
   - Do not write placeholder values.
   - Preserve the directory structure.

   ```markdown
   ---
   date: [Current date and time with timezone in ISO format]
   git_commit: [Current commit hash]
   branch: [Current branch name]
   repository: [Repository name]
   topic: "[User's Question/Topic]"
   tags: [research, codebase, relevant-component-names]
   status: [complete|in_progress]
   last_updated: [Current date in YYYY-MM-DD format]
   last_updated_by: null
   last_updated_note: null
   ---

   # Research: [User's Question/Topic]

   **Date**: [Current date and time with timezone from step 5]
   **Git Commit**: [Current commit hash from step 5]
   **Branch**: [Current branch name from step 5]
   **Repository**: [Repository name]

   ## Research Question
   [Original user query]

   ## Summary
   [High-level documentation of what was found, answering the user's question by describing what exists]

   ## Detailed Findings

   ### [Component/Area 1]
   - Description of what exists ([file.ext:line](link))
   - How it connects to other components
   - Current implementation details (without evaluation)

   ### [Component/Area 2]
   ...

   ## Code References
   - `path/to/file.py:123` - Description of what's there
   - `another/file.ts:45-67` - Description of the code block

   ## Architecture Documentation
   [Current patterns, conventions, and design implementations found in the codebase]

   ## Related Research
   [Links to other research documents in .coding-agent/research/]

   ## Open Questions
   [Only include this section when there are genuine unresolved questions worth asking the user about.]
   ```

7. Add GitHub permalinks when needed.
   - Check branch and status with `git branch --show-current` and `git status`.
   - Generate GitHub permalinks only when the repo is on GitHub and you can confirm the commit is available on the remote.
   - Get repo info with `gh repo view --json owner,name`.
   - Format links as `https://github.com/{owner}/{repo}/blob/{commit}/{file}#L{line}`.
   - If GitHub or `gh` is unavailable, keep local file references.

8. Present findings.
   - Give a concise summary.
   - Include key file references.

9. Handle open questions.
   - Use this step only when there are genuine unresolved questions.
   - Present each item from `## Open Questions` one at a time.
   - Wait for the user's answer before moving to the next.
   - Update the document with the answer.
   - Move resolved items out of `Open Questions`.
   - Fold answers into the relevant sections.
   - Spawn new sub-agents if an answer creates new research needs.
   - After all questions are resolved, ask about follow-up questions.

10. Handle follow-up research.
    - Append follow-up material to the same research document.
    - Update `last_updated`.
    - Add or update `last_updated_by`.
    - Add or update `last_updated_note: "Added follow-up research for [brief description]"`.
    - Add `## Follow-up Research [timestamp]`.
    - Spawn new sub-agents as needed.
    - Keep updating the same document on disk.

## Notes

- Always use parallel Task agents.
- Always run fresh research.
- Always use concrete file paths and line numbers.
- Make the document self-contained.
- Keep prompts focused on read-only documentation.
- Document cross-component connections and interactions.
- Include temporal context for when the research happened.
- Link to GitHub when possible.
- Keep the main agent focused on synthesis, but verify the key source files and line references yourself before finalizing.
- Have sub-agents document examples and usage patterns as they exist.
- **CRITICAL**: You and all sub-agents are documentarians, not evaluators.
- **REMEMBER**: Document what IS, not what SHOULD BE.
- **NO RECOMMENDATIONS**: Only describe the current state of the codebase.
- **File reading**: Always read mentioned files fully before spawning sub-tasks.
- **Critical ordering**: Follow the numbered steps exactly.
  - Always read mentioned files first before spawning sub-tasks.
  - Always wait for all sub-agents before synthesizing.
  - Always gather metadata before writing the document.
  - Never write the research document with placeholder values.
  - Always preserve the exact directory structure.
  - This keeps paths correct for editing and navigation.
- **Frontmatter consistency**:
  - Always include frontmatter at the top of research documents.
  - Keep frontmatter fields consistent across all research docs.
  - On follow-up updates, add or update follow-up fields such as `last_updated_by` and `last_updated_note`.
  - Use snake_case for multi-word fields such as `last_updated` and `git_commit`.
  - Keep tags relevant to the research topic and the components studied.
- Use `status: complete` when the research is done and there are no meaningful unresolved questions. Otherwise keep it `in_progress` until follow-up work is done.
