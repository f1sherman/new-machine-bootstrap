---
name: deep-research
description: >
  Use when users need in-depth research on a complex topic or a comprehensive
  report requiring multiple sources and synthesis. Avoid for simple fact-finding,
  single-source lookups, or quick exploratory searches.
---

# Deep Research Skill

## Core Purpose

Transforms research questions into detailed reports using a three-agent system: a lead orchestrator, multiple researcher agents executing parallel searches, and a report-writer synthesizing findings.

## Agent Architecture

**Lead Agent (Orchestrator)**: Interviews users, plans research threads, coordinates subagents using Agent and AskUserQuestion tools.

**Researcher Agents**: Execute focused investigations on assigned subtopics, employing WebSearch, WebFetch, and Write tools to save structured notes.

**Report-Writer Agent**: Synthesizes research notes into final reports using Read, Glob, and Write tools exclusively.

## Five-Phase Research Process

**Phase 1: Interview**
2-3 rounds of user interviews covering objectives, depth, audience, key questions, time constraints, and scope.

**Phase 2: Landscape Mapping**
3-5 broad searches to map the topic landscape, identifying 10+ research threads, documented in `research_plan.md`.

**Phase 3: Parallel Research**
Launch 10+ researcher agents in parallel, each saving findings to `research_notes/[subtopic].md` with:
- Summary
- Key findings
- Sources with URLs
- Notable quotes
- Identified gaps

**Phase 4: Synthesis**
Spawn report-writer agent to synthesize notes into a comprehensive report with:
- Executive summary
- Critical analysis organized by theme
- Numbered citations
- Identified limitations and conflicting information

**Phase 5: Delivery**
Deliver output files and summarize key findings for user follow-up.

## Quality Standards

- Prioritize authoritative, recent sources
- Cross-reference claims across multiple researcher notes
- Distinguish facts from expert opinions
- Clearly identify conflicting information or research limitations
- Include direct URLs for all cited sources
