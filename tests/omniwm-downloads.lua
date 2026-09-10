local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local downloads = require("omniwm_downloads").new()
local failures = 0

local function assertEqual(expected, actual, message)
  if expected ~= actual then
    failures = failures + 1
    io.stderr:write(string.format(
      "FAIL: %s (expected %s, got %s)\n",
      message,
      tostring(expected),
      tostring(actual)
    ))
  end
end

local lockNotifications = {}
assertEqual(true, downloads.beginOperation(function() end), "first operation starts")
assertEqual(false, downloads.beginOperation(function(message)
  table.insert(lockNotifications, message)
end), "shortcut and recovery operations exclude each other")
assertEqual(1, #lockNotifications, "blocked operation reports one error")
downloads.finishOperation()
assertEqual(true, downloads.beginOperation(function() end), "operation can restart after completion")
downloads.finishOperation()

local readiness = {checks = 0, retries = 0, recoveries = 0, notify = {}}
downloads.recoverWhenReady({
  attempts = 3,
  check = function(callback)
    readiness.checks = readiness.checks + 1
    callback(nil, readiness.checks < 3 and "IPC unavailable" or nil)
  end,
  retry = function(callback)
    readiness.retries = readiness.retries + 1
    callback()
  end,
  recover = function()
    readiness.recoveries = readiness.recoveries + 1
  end,
  notify = function(message)
    table.insert(readiness.notify, message)
  end,
})
assertEqual(3, readiness.checks, "startup recovery retries readiness errors")
assertEqual(2, readiness.retries, "startup recovery schedules bounded retries")
assertEqual(1, readiness.recoveries, "startup recovery runs once after readiness")
assertEqual(0, #readiness.notify, "eventual readiness is quiet")

local unavailable = {checks = 0, retries = 0, recoveries = 0, notify = {}}
downloads.recoverWhenReady({
  attempts = 2,
  check = function(callback)
    unavailable.checks = unavailable.checks + 1
    callback(nil, "IPC unavailable")
  end,
  retry = function(callback)
    unavailable.retries = unavailable.retries + 1
    callback()
  end,
  recover = function()
    unavailable.recoveries = unavailable.recoveries + 1
  end,
  notify = function(message)
    table.insert(unavailable.notify, message)
  end,
})
assertEqual(2, unavailable.checks, "startup readiness retries are bounded")
assertEqual(1, unavailable.retries, "final readiness failure does not retry")
assertEqual(0, unavailable.recoveries, "unready OmniWM does not run recovery")
assertEqual(1, #unavailable.notify, "final readiness failure reports once")

local recheckEvents = {notify = {}, show = {}, done = 0}
local recheckActions = {
  isFinder = function(window)
    return window.app and window.app.bundleId == "com.apple.finder"
  end,
  notify = function(message)
    table.insert(recheckEvents.notify, message)
  end,
  show = function(id, callback)
    table.insert(recheckEvents.show, id)
    callback(nil, nil)
  end,
  done = function()
    recheckEvents.done = recheckEvents.done + 1
  end,
}
assertEqual(true, downloads.shouldCreateAfterLock({}, recheckActions), "empty recheck permits creation")
assertEqual(false, downloads.shouldCreateAfterLock({{
  id = "finder-existing",
  app = {bundleId = "com.apple.finder"},
}}, recheckActions), "existing Finder blocks stale creation")
assertEqual("finder-existing", recheckEvents.show[1], "existing Finder is shown")
assertEqual(1, recheckEvents.done, "existing Finder releases creation lock")

local pendingShow
assertEqual(true, downloads.beginOperation(function() end), "shortcut operation takes shared lock")
downloads.shouldCreateAfterLock({{
  id = "finder-existing",
  app = {bundleId = "com.apple.finder"},
}}, {
  isFinder = recheckActions.isFinder,
  notify = function() end,
  show = function(_, callback)
    pendingShow = callback
  end,
  done = downloads.finishOperation,
})
assertEqual(false, downloads.beginOperation(function() end), "recovery is blocked during shortcut show")
pendingShow(nil, nil)
assertEqual(true, downloads.beginOperation(function() end), "shared lock releases after shortcut show")
downloads.finishOperation()

local otherOwnerEvents = {notify = {}, done = 0}
assertEqual(false, downloads.shouldCreateAfterLock({{
  id = "other-window",
  app = {bundleId = "com.example.other"},
}}, {
  isFinder = recheckActions.isFinder,
  notify = function(message)
    table.insert(otherOwnerEvents.notify, message)
  end,
  show = function(_, callback)
    callback(nil, nil)
  end,
  done = function()
    otherOwnerEvents.done = otherOwnerEvents.done + 1
  end,
}), "other scratchpad owner blocks stale creation")
assertEqual(1, #otherOwnerEvents.notify, "other owner reports one error")
assertEqual(1, otherOwnerEvents.done, "other owner releases creation lock")

local function harness(window, scratchpad, queryError, target, targetError, assignError, showError)
  local calls = {notify = {}, query = 0, target = 0, assign = 0, show = {}, done = 0}
  local pendingTargetCallback
  downloads.assignNewScratchpad(window, {
    notify = function(message)
      table.insert(calls.notify, message)
    end,
    queryScratchpad = function(callback)
      calls.query = calls.query + 1
      callback(scratchpad, queryError)
    end,
    queryTarget = function(_, callback)
      calls.target = calls.target + 1
      pendingTargetCallback = callback
    end,
    assign = function(callback)
      calls.assign = calls.assign + 1
      callback(nil, assignError)
    end,
    show = function(id, callback)
      table.insert(calls.show, id)
      callback(nil, showError)
    end,
    done = function()
      calls.done = calls.done + 1
    end,
  })
  if pendingTargetCallback then
    pendingTargetCallback(target, targetError)
  end
  return calls
end

local focusedWindow = {id = "finder-1", isFocused = true}
local focused = harness(focusedWindow, {}, nil, focusedWindow)
assertEqual(1, focused.query, "new window queries scratchpad")
assertEqual(1, focused.target, "target focus is revalidated")
assertEqual(1, focused.assign, "focused target is assigned")
assertEqual("finder-1", focused.show[1], "assigned target is shown")
assertEqual(1, focused.done, "successful assignment completes creation")

local lostFocus = harness(focusedWindow, {}, nil, {id = "finder-1", isFocused = false})
assertEqual(0, lostFocus.assign, "target that lost focus is not assigned")
assertEqual(1, #lostFocus.notify, "lost focus reports one error")
assertEqual(1, lostFocus.done, "lost focus completes creation")

local existing = harness(focusedWindow, {{id = "finder-1"}})
assertEqual(0, existing.target, "existing scratchpad needs no focus query")
assertEqual(0, existing.assign, "existing scratchpad is not reassigned")
assertEqual("finder-1", existing.show[1], "existing scratchpad is shown")

local other = harness(focusedWindow, {{id = "other-window"}})
assertEqual(0, other.assign, "other scratchpad owner is preserved")
assertEqual(1, #other.notify, "other scratchpad owner reports one error")

local queryFailure = harness(focusedWindow, nil, "query failed")
assertEqual(0, queryFailure.assign, "query failure stops assignment")
assertEqual("query failed", queryFailure.notify[1], "query failure is reported")

local targetFailure = harness(focusedWindow, {}, nil, nil, "target failed")
assertEqual(0, targetFailure.assign, "target query failure stops assignment")
assertEqual("target failed", targetFailure.notify[1], "target query failure is reported")

local assignFailure = harness(focusedWindow, {}, nil, focusedWindow, nil, "assign failed")
assertEqual(0, #assignFailure.show, "assignment failure does not show target")
assertEqual("assign failed", assignFailure.notify[1], "assignment failure is reported")

local showFailure = harness(focusedWindow, {}, nil, focusedWindow, nil, nil, "show failed")
assertEqual(1, #showFailure.notify, "show failure is reported once")
assertEqual("show failed", showFailure.notify[1], "show failure preserves its detail")

local function recoveryHarness(options)
  local calls = {events = {}, notify = {}, done = 0}
  local target = {id = "downloads", isVisible = options.visible ~= false}
  downloads.recoverScratchpad({
    scratchpad = options.scratchpad or {},
    downloadsWindows = options.downloadsWindows or {target},
    focusedWindow = options.focusedWindow,
    activeWorkspace = {number = 4},
  }, {
    navigate = function(id, callback)
      table.insert(calls.events, "navigate:" .. id)
      callback(nil, options.navigateError)
    end,
    confirmFocused = function(id, callback)
      table.insert(calls.events, "confirm-focused:" .. id)
      callback(target, options.focusError)
    end,
    revalidateAssignment = function(id, callback)
      table.insert(calls.events, "revalidate-assignment:" .. id)
      if options.assignmentOwnerChanged then
        callback(nil, "Scratchpad slot 1 gained another owner")
      elseif options.assignmentFocusLost then
        callback(nil, "The Downloads window lost focus before assignment")
      else
        callback(target, nil)
      end
    end,
    assign = function(callback)
      table.insert(calls.events, "assign")
      callback(nil, options.assignError)
    end,
    confirmAssigned = function(id, callback)
      table.insert(calls.events, "confirm-assigned:" .. id)
      if options.missingAssignment then
        callback(nil, nil)
      else
        callback(target, options.confirmError)
      end
    end,
    revalidateHide = function(id, callback)
      table.insert(calls.events, "revalidate-hide:" .. id)
      if options.hideOwnerChanged then
        callback(nil, "Scratchpad slot 1 changed owners")
      else
        local isVisible = target.isVisible
        if options.hiddenBeforeToggle then
          isVisible = false
        end
        callback({id = id, isVisible = isVisible}, nil)
      end
    end,
    hide = function(id, callback)
      table.insert(calls.events, "hide:" .. id)
      callback(nil, options.hideError)
    end,
    restoreWindow = function(id, callback)
      table.insert(calls.events, "restore-window:" .. id)
      callback(nil, options.restoreError)
    end,
    restoreWorkspace = function(number, callback)
      table.insert(calls.events, "restore-workspace:" .. number)
      callback(nil, options.restoreError)
    end,
    notify = function(message)
      table.insert(calls.notify, message)
    end,
    done = function()
      calls.done = calls.done + 1
    end,
  })
  return calls
end

local occupiedRecovery = recoveryHarness({
  scratchpad = {{id = "owner"}},
  focusedWindow = {id = "previous"},
})
assertEqual("", table.concat(occupiedRecovery.events, ","), "occupied scratchpad is unchanged")
assertEqual(1, #occupiedRecovery.notify, "occupied scratchpad reports one error")
assertEqual(1, occupiedRecovery.done, "occupied scratchpad completes")

local absentRecovery = recoveryHarness({
  downloadsWindows = {},
  focusedWindow = {id = "previous"},
})
assertEqual("", table.concat(absentRecovery.events, ","), "absent Downloads window is unchanged")
assertEqual(0, #absentRecovery.notify, "absent Downloads window is a quiet no-op")
assertEqual(1, absentRecovery.done, "absent Downloads window completes")

local ambiguousRecovery = recoveryHarness({
  downloadsWindows = {{id = "downloads-1"}, {id = "downloads-2"}},
  focusedWindow = {id = "previous"},
})
assertEqual("", table.concat(ambiguousRecovery.events, ","), "ambiguous Downloads windows are unchanged")
assertEqual(1, #ambiguousRecovery.notify, "ambiguous Downloads windows report one error")
assertEqual(1, ambiguousRecovery.done, "ambiguous Downloads windows complete")

local recovered = recoveryHarness({focusedWindow = {id = "previous"}})
assertEqual(
  "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,revalidate-hide:downloads,hide:downloads,restore-window:previous",
  table.concat(recovered.events, ","),
  "visible Downloads window recovery order"
)
assertEqual(0, #recovered.notify, "successful recovery has no error")
assertEqual(1, recovered.done, "successful recovery completes once")

local workspaceRestore = recoveryHarness({visible = false})
assertEqual(
  "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,revalidate-hide:downloads,restore-workspace:4",
  table.concat(workspaceRestore.events, ","),
  "hidden recovery restores the prior workspace"
)
assertEqual(1, workspaceRestore.done, "workspace restoration completes once")

local focusedTargetRestore = recoveryHarness({
  focusedWindow = {id = "downloads"},
})
assertEqual(
  "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,revalidate-hide:downloads,hide:downloads,restore-workspace:4",
  table.concat(focusedTargetRestore.events, ","),
  "focused Downloads recovery restores its prior workspace"
)
assertEqual(0, #focusedTargetRestore.notify, "focused Downloads recovery has no error")
assertEqual(1, focusedTargetRestore.done, "focused Downloads recovery completes once")

local windowRestoreFailure = recoveryHarness({
  focusedWindow = {id = "previous"},
  restoreError = "window restore failed",
})
assertEqual("window restore failed", windowRestoreFailure.notify[1], "window restore failure is reported")
assertEqual(1, #windowRestoreFailure.notify, "window restore failure reports one error")
assertEqual(1, windowRestoreFailure.done, "window restore failure completes once")

local workspaceRestoreFailure = recoveryHarness({
  visible = false,
  restoreError = "workspace restore failed",
})
assertEqual("workspace restore failed", workspaceRestoreFailure.notify[1], "workspace restore failure is reported")
assertEqual(1, #workspaceRestoreFailure.notify, "workspace restore failure reports one error")
assertEqual(1, workspaceRestoreFailure.done, "workspace restore failure completes once")

local hiddenBeforeToggle = recoveryHarness({
  focusedWindow = {id = "previous"},
  hiddenBeforeToggle = true,
})
assertEqual(
  "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,revalidate-hide:downloads,restore-window:previous",
  table.concat(hiddenBeforeToggle.events, ","),
  "already hidden scratchpad is not toggled"
)
assertEqual(1, hiddenBeforeToggle.done, "already hidden recovery releases the lock once")

local recoveryFailures = {
  {"navigate", {navigateError = "navigate failed"}, "navigate:downloads,restore-window:previous"},
  {"focus", {focusError = "focus failed"}, "navigate:downloads,confirm-focused:downloads,restore-window:previous"},
  {"assignment focus", {assignmentFocusLost = true}, "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,restore-window:previous"},
  {"assignment owner", {assignmentOwnerChanged = true}, "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,restore-window:previous"},
  {"assign", {assignError = "assign failed"}, "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,restore-window:previous"},
  {"confirm", {confirmError = "confirm failed"}, "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,restore-window:previous"},
  {"missing assignment", {missingAssignment = true}, "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,restore-window:previous"},
  {"hide owner", {hideOwnerChanged = true}, "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,revalidate-hide:downloads,restore-window:previous"},
  {"hide", {hideError = "hide failed"}, "navigate:downloads,confirm-focused:downloads,revalidate-assignment:downloads,assign,confirm-assigned:downloads,revalidate-hide:downloads,hide:downloads,restore-window:previous"},
}
for _, failureCase in ipairs(recoveryFailures) do
  failureCase[2].focusedWindow = {id = "previous"}
  local failedRecovery = recoveryHarness(failureCase[2])
  assertEqual(failureCase[3], table.concat(failedRecovery.events, ","), failureCase[1] .. " failure order")
  assertEqual(1, #failedRecovery.notify, failureCase[1] .. " failure reports one error")
  assertEqual(1, failedRecovery.done, failureCase[1] .. " failure completes once")
end

if failures > 0 then
  os.exit(1)
end

print("PASS: OmniWM Downloads scratchpad assignment and locking cases")
