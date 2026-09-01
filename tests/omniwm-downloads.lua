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
assertEqual(true, downloads.beginCreation(function() end), "first creation starts")
assertEqual(false, downloads.beginCreation(function(message)
  table.insert(lockNotifications, message)
end), "second creation is blocked")
assertEqual(1, #lockNotifications, "blocked creation reports one error")
downloads.finishCreation()
assertEqual(true, downloads.beginCreation(function() end), "creation can restart after completion")
downloads.finishCreation()

local function harness(window, scratchpad, queryError, target, targetError, assignError)
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
    show = function(id)
      table.insert(calls.show, id)
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

if failures > 0 then
  os.exit(1)
end

print("PASS: OmniWM Downloads scratchpad assignment and locking cases")
