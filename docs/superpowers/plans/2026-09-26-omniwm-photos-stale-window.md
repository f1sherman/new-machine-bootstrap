# OmniWM Photos stale-window recovery implementation plan

Status: Self-approved

## Task 1: Add the failing behavioral test

**Files:**
- Create `tests/omniwm-photos.lua`

1. Test visible and local windows use exact focus without summon.
2. Test remote windows use exact summon.
3. Test `not_found` causes one fresh query and uses the replacement ID.
4. Test zero and multiple replacements stop safely.
5. Test non-`not_found` errors and a second failure are reported without retry loops.
6. Run `lua5.4 tests/omniwm-photos.lua` and require the stale-ID case to fail before implementation.

## Task 2: Implement bounded fresh-ID recovery

**Files:**
- Create `roles/macos/files/hammerspoon/omniwm_photos.lua`
- Modify `roles/macos/files/hammerspoon/omniwm.lua`

1. Implement the dependency-injected Photos orchestration helper.
2. Replace the direct Photos summon flow with the helper.
3. Preserve exact focus, launch, and ambiguity behavior.
4. Do not add any move, close, or resize command.
5. Run the focused test and Lua syntax checks.

## Task 3: Deploy and verify

**Files:**
- Modify `roles/macos/tasks/install_omniwm.yml`
- Modify `.github/workflows/integration-test.yml`

1. Deploy the new helper before the main Hammerspoon file.
2. Add the focused test to CI.
3. Run all focused OmniWM Lua tests.
4. Run Ansible syntax validation.
5. Review the diff for scope and forbidden live-window operations.
6. Commit, push, and create the pull request.

Live `⌃⌥P` verification remains pending because it can summon a live Photos window and requires user approval.
