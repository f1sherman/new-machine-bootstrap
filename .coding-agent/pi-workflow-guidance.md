# Direct Pi workflow guidance

Approved native follow-up, 2026-10-30. Keep poteto-mode as the direct Pi default without the retired workflow dependency. Preserve existing document locations because repositories already use ignore rules for them.

- Specs and plans use `docs/superpowers/`; specs use its `specs/` directory.
- Handoffs use `.superpowers/handoffs/` for creation and discovery.
- Check the actual document path before staging. Keep ignored documents local and never force-add them.
- Keep native execution, worktree isolation, verification, independent review, and publication gates.
- Restore the existing Pi current-spec tracker. The proposed new document directory and its tracking support are no longer needed.
- Do not move or delete existing documents. This previously committed plan stays in place.

Verify focused deployment on both personal hosts, native Pi loading, the existing tracking-to-resolver path, and Git ignore behavior for both document locations. Other clients' packages and settings remain outside this change.

Historical evidence. The prior routing comparison completed two repetitions per condition. Baseline and direct guidance selected poteto-mode twice each. Removing only the routing directive selected native execution twice. Total token counts were 2583/2583, 2457/2471, and 2505/2509. This was routing evidence, not task-quality or authorization-safety evidence. The temporary new-directory tracker repair and its capture-based checks were superseded by the decision to retain the original paths.
