# ChatGPT Chrome Duplicate Windows Plan

Status: Self-approved

1. Commit the approved design.
2. Add failing resolver tests for a matching preferred native window ID, a stale
   preferred ID, an invalid preferred ID, and the existing unique case.
3. Add a focused test for the Chrome preferred-window adapter.
4. Implement preferred native-ID selection without changing fallback semantics.
5. Update the OmniWM cheat sheet.
6. Run all focused tests and static checks.
7. Review the complete diff, commit it, and open a pull request.
8. Do not provision or reload Hammerspoon without explicit user approval.
