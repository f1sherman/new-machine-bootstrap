local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local router = require("omniwm_safari_router")
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

local function runCase(options)
  local events = {}
  local notifications = {}
  local focusCount = 0
  local resolveAttempts = 0
  router.route("https://example.com", {
    openURL = function(url)
      table.insert(events, "open:" .. url)
      return options.opened ~= false
    end,
    delay = function(callback)
      table.insert(events, "delay")
      callback()
    end,
    poll = function(predicate, callback)
      for _ = 1, 3 do
        local value
        predicate(function(result)
          value = result
        end)
        if value then
          callback(value, nil)
          return
        end
      end
      callback(nil, "target timeout")
    end,
    frontWindowID = function()
      table.insert(events, "front-id")
      if options.nativeID == false then
        return nil
      end
      return 105
    end,
    windows = function(callback)
      table.insert(events, "windows")
      callback(options.windowsResult or {}, options.windowsError)
    end,
    resolve = function(_, nativeID)
      resolveAttempts = resolveAttempts + 1
      table.insert(events, "resolve:" .. tostring(nativeID))
      if resolveAttempts <= (options.readinessFailures or 0) then
        return nil, "not ready"
      end
      return options.target, options.resolveError
    end,
    navigate = function(id, callback)
      table.insert(events, "navigate:" .. id)
      callback(nil, options.navigateError)
    end,
    pollFocused = function(id, callback)
      table.insert(events, "poll-focused:" .. id)
      callback(nil, options.focusError)
    end,
    focusSafari = function()
      focusCount = focusCount + 1
      table.insert(events, "focus-safari")
    end,
    notify = function(message)
      table.insert(notifications, message)
    end,
  })
  return events, notifications, focusCount
end

local events, notifications, focusCount = runCase({
  target = {id = "ow_105"},
  readinessFailures = 1,
})
assertEqual(
  "open:https://example.com,delay,front-id,windows,resolve:105,front-id,windows,resolve:105,navigate:ow_105,poll-focused:ow_105",
  table.concat(events, ","),
  "delayed successful route order"
)
assertEqual(0, #notifications, "successful notifications")
assertEqual(0, focusCount, "successful fallback focus")

local openEvents, openNotifications, openFocus = runCase({opened = false})
assertEqual("open:https://example.com", table.concat(openEvents, ","), "open failure stops")
assertEqual("Could not open the URL in Safari", openNotifications[1], "open failure message")
assertEqual(0, openFocus, "open failure does not focus")

local postOpenCases = {
  {"ID timeout", {nativeID = false}, "target timeout"},
  {"window query timeout", {windowsError = "query failed"}, "target timeout"},
  {"resolution timeout", {resolveError = "match failed"}, "target timeout"},
  {"navigation failure", {target = {id = "ow_105"}, navigateError = "navigate failed"}, "navigate failed"},
  {"focus failure", {target = {id = "ow_105"}, focusError = "focus failed"}, "focus failed"},
}
for _, case in ipairs(postOpenCases) do
  local caseEvents, caseNotifications, caseFocus = runCase(case[2])
  local openCount = 0
  local windowQueryCount = 0
  for _, event in ipairs(caseEvents) do
    if event:sub(1, 5) == "open:" then
      openCount = openCount + 1
    elseif event == "windows" then
      windowQueryCount = windowQueryCount + 1
    end
  end
  assertEqual(1, openCount, case[1] .. " URL open count")
  if case[1] == "ID timeout" then
    assertEqual(0, windowQueryCount, "ID timeout skips window queries")
  end
  assertEqual(1, caseFocus, case[1] .. " fallback focus count")
  assertEqual(case[3], caseNotifications[1], case[1] .. " notification")
end

if failures > 0 then
  os.exit(1)
end

print("PASS: OmniWM Safari navigation state machine")
