---
name: deep-research
description: >
  Use when users need in-depth research on a complex topic or a comprehensive
  report requiring multiple sources and synthesis. Avoid for simple fact-finding,
  single-source lookups, or quick exploratory searches.
---

# Deep Research

## Core

Turn research questions into detailed reports.

Use a three-agent system:

- Lead orchestrator: interview the user, plan threads, coordinate subagents with `Agent` and `AskUserQuestion`.
- Researcher agents: run focused investigations in parallel with `WebSearch`, `WebFetch`, and `Write`.
- Report-writer agent: synthesize notes with `Read`, `Glob`, and `Write` only.

## Five Phases

### Phase 1: Interview

Do 2-3 rounds of user interviews.
Cover objective, depth, audience, key questions, time constraints, and scope.

### Phase 2: Landscape Mapping

Run 3-5 broad searches.
Map the topic landscape.
Identify 10+ research threads.
Record them in `research_plan.md`.

### Phase 3: Parallel Research

Launch 10+ researcher agents in parallel.
Each writes `research_notes/[subtopic].md` with:
- Summary
- Key findings
- Sources with URLs
- Notable quotes
- Identified gaps

### Phase 4: Synthesis

Spawn the report-writer agent.
Produce a comprehensive report with:
- Executive summary
- Critical analysis by theme
- Numbered citations
- Limitations and conflicting information

### Phase 5: Delivery

Deliver the output files.
Summarize the key findings for follow-up.

## Standards

- Prioritize authoritative, recent sources.
- Cross-reference claims across multiple researcher notes.
- Separate facts from expert opinion.
- Call out conflicts and limitations.
- Include direct URLs for every cited source.
