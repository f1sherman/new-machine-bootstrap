local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local router = require("omniwm_slack_router")
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

local workSafari = {id = "ow_work"}

local function run(overrides)
  local calls = {}
  local target = workSafari
  local deps = {
    openTab = function(target, url)
      table.insert(calls, "open:" .. target.id .. ":" .. url)
      return true, nil
    end,
    navigate = function(id, callback)
      table.insert(calls, "navigate:" .. id)
      callback({}, nil)
    end,
    fallback = function(url)
      table.insert(calls, "fallback:" .. url)
    end,
    notify = function(message)
      table.insert(calls, "notify:" .. message)
    end,
  }
  for key, value in pairs(overrides or {}) do
    if key == "target" then
      target = value
    else
      deps[key] = value
    end
  end
  router.route("https://example.test", target, deps)
  return calls
end

assertEqual(
  "open:ow_work:https://example.test,navigate:ow_work",
  table.concat(run(), ","),
  "successful Slack routing"
)
assertEqual(
  "fallback:https://example.test",
  table.concat(run({target = false}), ","),
  "missing Work Safari fallback"
)

local createFailureCalls = run({
  openTab = function()
    return false, "Could not open Work Safari tab"
  end,
})
assertEqual(
  "notify:Could not open Work Safari tab,fallback:https://example.test",
  table.concat(createFailureCalls, ","),
  "tab creation fallback"
)

local todoistFailureCalls = run({
  openTab = function()
    return false, nil
  end,
  openError = "Could not open the Todoist link in Personal Safari",
})
assertEqual(
  "notify:Could not open the Todoist link in Personal Safari,fallback:https://example.test",
  table.concat(todoistFailureCalls, ","),
  "Todoist tab creation fallback"
)

local navigationFailureCalls = run({
  navigate = function(_, callback)
    callback({}, "Could not focus Work Safari")
  end,
})
assertEqual(
  "open:ow_work:https://example.test,notify:Could not focus Work Safari",
  table.concat(navigationFailureCalls, ","),
  "navigation failure does not duplicate URL"
)

if failures > 0 then
  os.exit(1)
end

print("PASS: Slack Work Safari routing state machine")
