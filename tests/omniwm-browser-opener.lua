local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local opener = require("omniwm_browser_opener")
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

local function runCase(opened, focused)
  local events = {}
  local notifications = {}
  local result = opener.open(
    "https://example.com",
    "com.apple.Safari",
    "Safari",
    {
      openURL = function(url, bundleID)
        table.insert(events, "open:" .. url .. ":" .. bundleID)
        return opened
      end,
      focus = function(bundleID)
        table.insert(events, "focus:" .. bundleID)
        return focused
      end,
      notify = function(message)
        table.insert(notifications, message)
      end,
    }
  )
  return result, events, notifications
end

local result, events, notifications = runCase(true, true)
assertEqual(true, result, "successful result")
assertEqual(
  "open:https://example.com:com.apple.Safari,focus:com.apple.Safari",
  table.concat(events, ","),
  "successful operation order"
)
assertEqual(0, #notifications, "successful notifications")

result, events, notifications = runCase(false, true)
assertEqual(false, result, "open failure result")
assertEqual(1, #events, "open failure does not focus")
assertEqual("Could not open the URL in Safari", notifications[1], "open failure message")

result, events, notifications = runCase(true, false)
assertEqual(false, result, "focus failure result")
assertEqual(2, #events, "focus failure operation count")
assertEqual("Could not focus Safari", notifications[1], "focus failure message")

if failures > 0 then
  os.exit(1)
end

print("PASS: OmniWM browser opener")
