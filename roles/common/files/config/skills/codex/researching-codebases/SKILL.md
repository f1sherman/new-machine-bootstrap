---
name: personal:research-codebase
description: >
  Conduct comprehensive codebase research and generate documentation.
  Use when the user asks how the current system works or requests a codebase deep dive.
---

# Research Codebase

Map the codebase as it exists today. Answer with evidence, paths, and line references.

## Boundary
- Document only.
- No critique.
- Do not identify problems.
- Do not evaluate the implementation.
- No recommendations.
- No improvements unless the user explicitly asks.
- No root cause analysis unless the user explicitly asks.
- No future enhancements unless the user explicitly asks.
- Describe what exists, where it exists, how it works, and how components interact.
- Build a technical map of the current system.

## Start

If the user has not provided a specific research question yet, respond with:
```
I'm ready to research the codebase. Please provide your research question or area of interest, and I'll analyze it thoroughly by exploring relevant components and connections.
```

Then wait.

## Workflow

1. **Read mentioned files first.**
   - If the user names files, docs, JSON, or accessible tickets, read them fully first.
   - Use your available file-reading tools to read the full file, not partial snippets.
   - If a file is too large for one read, read it in chunks until you have full coverage before moving on.
   - Read mentioned files before searching the wider codebase.
   - Get full context before decomposing the research.

2. **Decompose the question.**
   - Break the query into research areas.
   - Think through patterns, connections, and architectural implications.
   - Identify the components, patterns, or concepts to inspect.
   - Create a research plan with your available planning or task-tracking tools.
   - Select the relevant directories, files, and architectural patterns.

3. **Run the research loop.**
   - Pass 1, discovery: use `rg`, `rg --files`, and directory listings to find candidate files.
   - Pass 2, deep reads: read the most relevant files fully.
   - Pass 3, patterns/tests: find similar patterns, entry points, and tests.
   - Keep short notes with `file:line` references as you go.
   - If the user explicitly asks for web research, include links in the report.

4. **Document findings.**
   - Locate the relevant files and components.
   - Document how specific code works.
   - Include examples of existing patterns without evaluation.

5. **Synthesize.**
   - Treat the live codebase as the primary source of truth.
   - Connect findings across components.
   - Include specific file paths and line numbers.
   - Verify every path.
   - Highlight patterns, connections, and architectural decisions only when they are directly evidenced in code or docs.
   - Answer the user's question with concrete evidence.

6. **Gather metadata before writing.**
   - Run `~/.local/bin/spec-metadata` to generate the required metadata.
   - If `spec-metadata` is unavailable or incomplete, derive the missing metadata from git, the repo, and the current date/time. Do not invent values.
   - Use the filename `.coding-agent/research/YYYY-MM-DD-ENG-XXXX-description.md`.
   - Format:
     - `YYYY-MM-DD` is today's date.
     - `ENG-XXXX` is the ticket number, omitted if there is no ticket.
     - `description` is a short kebab-case research topic.
   - Examples:
     - With ticket: `2025-01-08-ENG-1478-parent-child-tracking.md`
     - Without ticket: `2025-01-08-authentication-flow.md`

7. **Write the research document.**
   - Use the metadata from step 6.
   - Preserve the directory structure exactly.
   - Write YAML frontmatter first, then content:
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

     **Date**: [Current date and time with timezone from step 6]
     **Git Commit**: [Current commit hash from step 6]
     **Branch**: [Current branch name from step 6]
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

     ## Open Questions (if any)
     [Only include this section when there are genuine unresolved questions worth asking the user about.]
     ```

8. **Add remote permalinks if applicable.**
   - Check the branch and status with `git branch --show-current` and `git status`.
   - Check whether the specific commit you are citing is available on the remote before generating permalinks.
   - If the repo host and remote commit are confirmed, derive the host from the remote or repository info before building commit-based permalinks.
   - Build permalinks with that confirmed host.
   - If the relevant content exists only in local uncommitted changes or is not reachable at a stable remote commit, keep local file references.
   - If the repo host or auth is unavailable, keep local file references instead of guessing.

9. **Present findings.**
   - Give a concise summary.
   - Include key file references for navigation.
   - Ask for follow-up questions or clarification.

10. **Handle follow-up research.**
   - Append follow-up questions to the same research document only when they stay within the same research topic.
   - If the scope shifts materially, start a new research document and cross-link it.
   - Update `last_updated` in frontmatter.
   - Add or update `last_updated_by` with the current agent or session identifier.
   - Add or update `last_updated_note: "Added follow-up research for [brief description]"`.
   - Add `## Follow-up Research [timestamp]`.
   - Keep updating the same document on disk.

## Notes
- Run fresh research every time. Do not rely only on existing research documents.
- Use concrete file paths and line numbers for developer reference.
- Keep research documents self-contained.
- Document cross-component connections and system interactions.
- Include temporal context for when the research was conducted.
- Link to the remote host when stable permalinks are available.
- Documentarian only.
- Record what is, not what should be.
- No recommendations.
- Always read mentioned files fully before wider searching.
- Follow the numbered steps exactly.
  - Always read mentioned files first before deeper research.
  - Always gather metadata before writing the document.
  - Never write the research document with placeholder values.
  - Always preserve the exact directory structure.
  - This keeps paths correct for editing and navigation.
- Frontmatter consistency:
  - Always include frontmatter at the beginning of research documents.
  - Keep frontmatter fields consistent across research documents.
  - On follow-up updates, add or update follow-up fields such as `last_updated_by` and `last_updated_note`.
  - Use snake_case for multi-word field names, such as `last_updated` and `git_commit`.
  - Keep tags relevant to the research topic and the components studied.
- Use `status: complete` only when there are no unresolved open questions. Otherwise keep it `in_progress` until follow-up work is done.
- Include `## Open Questions` only when there are genuine unresolved questions worth asking the user about.
