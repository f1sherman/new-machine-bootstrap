local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local router = require("omniwm_chatgpt_router")
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
  local fallbackCount = 0
  local notifications = {}
  local focusCalls = 0
  local deps = {
    focus = function(id, callback)
      focusCalls = focusCalls + 1
      table.insert(events, "focus:" .. id)
      callback(nil, options.focusErrors and options.focusErrors[focusCalls] or nil)
    end,
    frontWindowID = function()
      table.insert(events, "front-id")
      return options.chromeWindowID, options.frontWindowError
    end,
    confirmFocused = function(id, callback)
      table.insert(events, "confirm:" .. id)
      callback(nil, options.confirmError)
    end,
    createTab = function(windowID, url)
      table.insert(events, "create:" .. tostring(windowID) .. ":" .. url)
      return options.created, options.createError
    end,
    fallback = function()
      fallbackCount = fallbackCount + 1
      table.insert(events, "fallback")
    end,
    notify = function(message)
      table.insert(notifications, message)
    end,
  }
  router.route({id = "ow_chrome"}, "https://example.com", deps)
  return events, fallbackCount, notifications
end

local events, fallbackCount = runCase({chromeWindowID = 42, created = true})
assertEqual(
  "focus:ow_chrome,front-id,confirm:ow_chrome,create:42:https://example.com,focus:ow_chrome",
  table.concat(events, ","),
  "successful route order"
)
assertEqual(0, fallbackCount, "successful route fallback count")

local preCreationCases = {
  {"initial focus failure", {focusErrors = {"focus failed"}}},
  {"front ID failure", {frontWindowError = "no front window"}},
  {"focus confirmation failure", {chromeWindowID = 42, confirmError = "focus changed"}},
  {"tab creation failure", {chromeWindowID = 42, created = false, createError = "create failed"}},
}
for _, case in ipairs(preCreationCases) do
  local _, count = runCase(case[2])
  assertEqual(1, count, case[1] .. " fallback count")
end

local _, partialFallbacks, partialNotifications = runCase({
  chromeWindowID = 42,
  created = true,
  createError = "activation failed",
})
assertEqual(0, partialFallbacks, "partial creation does not fall back")
assertEqual("activation failed", partialNotifications[1], "partial creation reports error")

local _, finalFocusFallbacks, finalFocusNotifications = runCase({
  chromeWindowID = 42,
  created = true,
  focusErrors = {nil, "final focus failed"},
})
assertEqual(0, finalFocusFallbacks, "final focus failure does not fall back")
assertEqual("final focus failed", finalFocusNotifications[1], "final focus failure reports error")

if failures > 0 then
  os.exit(1)
end

print("PASS: ChatGPT Chrome routing state machine")
