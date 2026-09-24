package.path = "roles/macos/files/hammerspoon/?.lua;" .. package.path
package.loaded.omniwm_cheatsheet = {new = function() return {toggle = function() end} end}

local events = {}
local windows = {}
local navigationError
local tabError
local activationError
local senderBundle = "com.openai.codex"
hs = {
  logger = {new = function() return {i = function() end} end},
  timer = {doAfter = function() end},
  hotkey = {bind = function() return {} end},
  application = {
    applicationForPID = function()
      return {bundleID = function() return senderBundle end}
    end,
    get = function() return nil end,
    launchOrFocusByBundleID = function(bundle)
      table.insert(events, "focus:" .. bundle)
      return true
    end,
  },
  http = {urlParts = function(url)
    return {host = url == "https://fastmail.com/mail" and "fastmail.com" or "example.test"}
  end},
  base64 = {decode = function() return "Safari:42" end},
  osascript = {applescript = function(script)
    table.insert(events, "tab:" .. (script:find('application "Safari"', 1, true) and "safari" or "chrome"))
    if script:find("make new tab", 1, true) then
      if tabError then return false, tabError end
      return true, 1
    end
    if activationError then return false, activationError end
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
omniwm.windows = function(callback) callback(windows, nil) end
omniwm.activeWorkspace = function(callback) callback({number = 4}, nil) end
omniwm.run = function(args, callback)
  table.insert(events, table.concat(args, ":"))
  callback(nil, navigationError)
end
omniwm.poll = function(_, _, callback) callback({isFocused = true}, nil) end
omniwm.notify = function(message) table.insert(events, "notify:" .. message) end

local failures = 0
local function check(expected, actual, name)
  if expected ~= actual then
    failures = failures + 1
    io.stderr:write(name .. ": expected " .. expected .. ", got " .. actual .. "\n")
  end
end
local function click(url)
  events = {}
  hs.urlevent.httpCallback(nil, nil, nil, url, 123)
  return table.concat(events, ",")
end
local personal = {id = "ow_native42", app = {bundleId = "com.apple.Safari"}, title = "Personal — Mail"}
local second = {id = "ow_native43", app = {bundleId = "com.apple.Safari"}, title = "Personal — Second"}
local url = "https://fastmail.com/mail"

windows = {personal}
check("tab:safari,tab:safari,window:navigate:ow_native42", click(url), "Fastmail opens in exact Personal window")
check("open:com.google.Chrome,focus:com.google.Chrome", click("https://example.test"), "other ChatGPT links keep Chrome")
windows = {}
check("open:com.apple.Safari", click(url), "absent Personal window falls back once")
windows = {personal, second}
check("notify:More than one Safari Personal window is managed by OmniWM,open:com.apple.Safari", click(url), "ambiguous Personal window falls back once")
windows = {personal}
tabError = "creation failed"
check("tab:safari,notify:Could not open the Safari tab: creation failed,open:com.apple.Safari", click(url), "tab failure falls back once")
tabError = nil
activationError = "activation failed"
check("tab:safari,tab:safari,notify:Safari opened the tab but could not select it: activation failed,window:navigate:ow_native42", click(url), "selection failure does not reopen link")
activationError = nil
navigationError = "navigate failed"
check("tab:safari,tab:safari,window:navigate:ow_native42,notify:navigate failed", click(url), "post-creation failure does not reopen link")
navigationError = nil
senderBundle = "com.mitchellh.ghostty"
windows = {{id = "ow_native44", app = {bundleId = "com.apple.Safari"}, title = "Development — Mail", workspace = {number = 4}}}
activationError = "activation failed"
check("tab:safari,tab:safari,notify:Safari opened the tab but could not select it: activation failed,window:focus:ow_native44", click(url), "Ghostty selection failure does not reopen link")

if failures > 0 then os.exit(1) end
print("PASS: ChatGPT Fastmail callback routing")
