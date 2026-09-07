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
  router.route("https://example.com", {
    openURL = function(url)
      table.insert(events, "open:" .. url)
      return options.opened ~= false
    end,
    after = function(callback)
      table.insert(events, "after")
      callback()
    end,
    frontWindowID = function()
      table.insert(events, "front-id")
      return options.nativeID or 105, options.idError
    end,
    windows = function(callback)
      table.insert(events, "windows")
      callback(options.windowsResult or {}, options.windowsError)
    end,
    resolve = function(_, nativeID)
      table.insert(events, "resolve:" .. tostring(nativeID))
      return options.target, options.resolveError
    end,
    navigate = function(id, callback)
      table.insert(events, "navigate:" .. id)
      callback(nil, options.navigateError)
    end,
    confirmFocused = function(id, callback)
      table.insert(events, "confirm:" .. id)
      callback(nil, options.confirmError)
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

local events, notifications, focusCount = runCase({target = {id = "ow_105"}})
assertEqual(
  "open:https://example.com,after,front-id,windows,resolve:105,navigate:ow_105,confirm:ow_105",
  table.concat(events, ","),
  "successful route order"
)
assertEqual(0, #notifications, "successful notifications")
assertEqual(0, focusCount, "successful fallback focus")

local openEvents, openNotifications, openFocus = runCase({opened = false})
assertEqual("open:https://example.com", table.concat(openEvents, ","), "open failure stops")
assertEqual("Could not open the URL in Safari", openNotifications[1], "open failure message")
assertEqual(0, openFocus, "open failure does not focus")

local postOpenCases = {
  {"ID failure", {idError = "ID failed"}, "ID failed"},
  {"window query failure", {windowsError = "query failed"}, "query failed"},
  {"resolution failure", {resolveError = "match failed"}, "match failed"},
  {"navigation failure", {target = {id = "ow_105"}, navigateError = "navigate failed"}, "navigate failed"},
  {"focus failure", {target = {id = "ow_105"}, confirmError = "focus failed"}, "focus failed"},
}
for _, case in ipairs(postOpenCases) do
  local caseEvents, caseNotifications, caseFocus = runCase(case[2])
  local openCount = 0
  for _, event in ipairs(caseEvents) do
    if event:sub(1, 5) == "open:" then
      openCount = openCount + 1
    end
  end
  assertEqual(1, openCount, case[1] .. " URL open count")
  assertEqual(1, caseFocus, case[1] .. " fallback focus count")
  assertEqual(case[3], caseNotifications[1], case[1] .. " notification")
end

if failures > 0 then
  os.exit(1)
end

print("PASS: OmniWM Safari navigation state machine")
