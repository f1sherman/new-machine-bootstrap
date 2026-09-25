package.path = "roles/macos/files/hammerspoon/?.lua;" .. package.path
package.loaded.omniwm_cheatsheet = {new = function() return {toggle = function() end} end}

local events = {}
local windows = {}
local windowsError
local menuSuccess = true
local safariRunning = true
local launchSuccess = true
local openTabError
local work = {
  id = "ow_work",
  app = {bundleId = "com.apple.Safari"},
  title = "Work — Start Page",
  workspace = {number = 9},
}
local createdWindows = {work}
hs = {
  logger = {new = function() return {i = function() end} end},
  timer = {doAfter = function() end},
  hotkey = {bind = function() return {} end},
  application = {
    applicationForPID = function()
      return {bundleID = function() return "com.tinyspeck.slackmacgap" end}
    end,
    get = function(bundle)
      if bundle ~= "com.apple.Safari" or not safariRunning then return nil end
      return {selectMenuItem = function(_, path)
        table.insert(events, "menu:" .. table.concat(path, "/"))
        if menuSuccess then windows = createdWindows end
        return menuSuccess
      end}
    end,
    launchOrFocusByBundleID = function(bundle)
      table.insert(events, "launch:" .. bundle)
      if launchSuccess then safariRunning = true end
      return launchSuccess
    end,
  },
  http = {urlParts = function() return {} end},
  base64 = {decode = function() return "Safari:42" end},
  osascript = {applescript = function(script)
    table.insert(events, script:find("make new tab", 1, true) and "create-tab" or "select-tab")
    if script:find("make new tab", 1, true) then
      if openTabError then return false, openTabError end
      return true, 1
    end
    return true, nil
  end},
  urlevent = {openURLWithBundle = function(_, bundle)
    table.insert(events, "open:" .. bundle)
    return true
  end},
  notify = {new = function()
    return {send = function() end}
  end},
}

local omniwm = require("omniwm")
omniwm.notify = function(message) table.insert(events, "notify:" .. message) end
omniwm.windows = function(callback) callback(windows, windowsError) end
omniwm.query = function(_, callback)
  callback({result = {payload = {windows = windows}}}, nil)
end
omniwm.run = function(args, callback)
  table.insert(events, table.concat(args, ":"))
  if args[1] == "window" and args[2] == "navigate" then
    work.isFocused = true
  end
  callback(nil, nil)
end
omniwm.poll = function(predicate, _, callback)
  predicate(function(result, err)
    callback(result or nil, err or (not result and "Timed out while waiting for OmniWM" or nil))
  end)
end

local failures = 0
local function check(expected, actual, name)
  if expected ~= actual then
    failures = failures + 1
    io.stderr:write(name .. ": expected " .. expected .. ", got " .. actual .. "\n")
  end
end
local function click()
  events = {}
  hs.urlevent.httpCallback(nil, nil, nil, "https://example.test/slack", 123)
  return table.concat(events, ",")
end

check(
  "menu:File/New Window/New Work Window,create-tab,select-tab,window:navigate:ow_work",
  click(),
  "missing Work window is created and receives the link"
)
check(
  "create-tab,select-tab,window:navigate:ow_work",
  click(),
  "existing Work window does not create another"
)
windows = {work, {id = "ow_other", app = {bundleId = "com.apple.Safari"}, title = "Work — Other"}}
check(
  "notify:More than one Safari Work window is managed by OmniWM",
  click(),
  "ambiguous Work window does not open elsewhere"
)
windows = {}
menuSuccess = false
check(
  "menu:File/New Window/New Work Window,notify:Could not create the Safari Work window",
  click(),
  "menu failure does not open another profile"
)
menuSuccess = true
createdWindows = {{
  id = "ow_personal",
  app = {bundleId = "com.apple.Safari"},
  title = "Personal — Start Page",
}}
check(
  "menu:File/New Window/New Work Window,notify:Timed out while waiting for OmniWM",
  click(),
  "unexpected profile is not given the Slack link"
)
createdWindows = {work}
windows = {}
windowsError = "window query failed"
check(
  "notify:window query failed",
  click(),
  "query failure does not open another profile"
)
windowsError = nil
windows = {}
safariRunning = false
check(
  "launch:com.apple.Safari,menu:File/New Window/New Work Window,create-tab,select-tab,window:navigate:ow_work",
  click(),
  "closed Safari starts before Work window creation"
)
windows = {}
safariRunning = false
launchSuccess = false
check(
  "launch:com.apple.Safari,notify:Could not launch Safari to create a Work window",
  click(),
  "Safari launch failure does not open another profile"
)
launchSuccess = true
safariRunning = true
windows = {work}
openTabError = "tab failed"
check(
  "create-tab,notify:Could not open the Safari tab: tab failed",
  click(),
  "tab failure does not open another profile"
)

if failures > 0 then os.exit(1) end
print("PASS: Slack Work Safari window creation")
