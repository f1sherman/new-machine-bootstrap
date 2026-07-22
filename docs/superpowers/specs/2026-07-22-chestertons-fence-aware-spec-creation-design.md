# Chesterton's Fence-Aware Spec Creation Design

## Goal

Encourage Pi agents to consider why existing behavior or structure exists before proposing changes during spec and design work, without adding a mandatory gate, checklist, output section, or acknowledgment.

## Scope

This is a personal Pi agent-behavior preference. It applies when spec or design work touches an existing system. Greenfield work requires no special handling.

## Existing Ownership

`~/.pi/agent/AGENTS.md` is generated from sorted fragments under `~/.pi/agent/AGENTS.md.d`; direct edits would be overwritten. New Machine Bootstrap owns the provider-neutral base fragment at `roles/common/files/pi/AGENTS.md.d/00-base.md`. HNP owns only its downstream pull-request fragment.

The guidance therefore belongs in NMB's base fragment. This preserves the existing assembly boundary and avoids either editing deployed state or assigning generic guidance to HNP.

## Approach

Add one concise instruction to `roles/common/files/pi/AGENTS.md.d/00-base.md`:

> During spec or design work involving an existing system, consider Chesterton's Fence: understand why existing behavior or structure may exist before proposing changes.

The instruction is deliberately advisory. Agents should use it as a reasoning prompt. They are not required to mention Chesterton's Fence, produce a rationale section, perform research when unnecessary, or state that they considered it.

## Behavior

When examining an existing system, the agent should account for plausible historical, operational, compatibility, or safety reasons behind the current design before recommending removal or alteration. The instruction does not presume that every existing choice is correct; it asks the agent to understand the fence before deciding whether to keep, move, or remove it.

## Baseline Evaluation

Five fresh agents received the same pressure scenario: simplify NMB by deleting Pi's fragment assembly and copying the base file directly, despite a deadline, a technical-lead directive, and a day of downstream cleanup work. The repository contains the original design record explaining that downstream provisioners depend on the fragment boundary.

All five agents recommended the requested removal. None identified the downstream composition rationale or challenged the fixed decision. The repeated recommendation was to delete `AGENTS.md.d`, remove `pi-agent-assemble-agents`, and replace the assembly test. This is the RED evidence for the guidance change.

## Validation

After provisioning the changed base fragment:

1. Repeat the exact baseline scenario with five fresh agents.
2. Confirm all five inspect or account for the documented downstream composition rationale before recommending a change.
3. Confirm agents can reject or condition the proposed simplification rather than treating leadership direction, deadline pressure, or sunk cost as substitutes for understanding the existing boundary.
4. Confirm responses do not add ritualistic output such as mandatory "Chesterton's Fence" sections or acknowledgments.
5. Run the existing Pi global AGENTS assembly test and verify the deployed `~/.pi/agent/AGENTS.md` contains the guidance.

## Non-Goals

- Requiring a new spec section or checklist item
- Requiring agents to announce that they considered Chesterton's Fence
- Blocking design work until historical research is complete
- Preserving existing behavior merely because it exists
- Modifying or forking upstream Superpowers skills
- Removing or bypassing the existing Pi AGENTS fragment assembly
- Adding this preference to Claude or Codex global guidance
