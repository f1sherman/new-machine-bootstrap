local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local source = require("omniwm_url_source")
local route = source.shouldRouteGhostty
local isSafariBrowserWindow = source.isSafariBrowserWindow
local isChatGPTSender = source.isChatGPTSender
local isChromeBrowserWindow = source.isChromeBrowserWindow
local resolveActiveChromeWindow = source.resolveActiveChromeWindow
local preferredChromeNativeWindowID = source.preferredChromeNativeWindowID
local normalizeNativeWindowID = source.normalizeNativeWindowID
local isDevelopmentSafariWindow = source.isDevelopmentSafariWindow
local resolveDevelopmentSafariWindow = source.resolveDevelopmentSafariWindow
local resolveSafariWindowByNativeID = source.resolveSafariWindowByNativeID
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

assertEqual(true, source.isSlackSender("com.tinyspeck.slackmacgap"), "Slack sender")
assertEqual(false, source.isSlackSender("com.apple.MobileSMS"), "non-Slack sender")
assertEqual(true, source.isTodoistSender("com.todoist.mac.Todoist"), "Todoist sender")
assertEqual(false, source.isTodoistSender("com.apple.MobileSMS"), "non-Todoist sender")

local personalSafari = {
  id = "ow_personal",
  app = {bundleId = "com.apple.Safari"},
  title = "Personal — Inbox",
  workspace = {number = 2},
}
assertEqual(true, source.isPersonalSafariWindow(personalSafari), "Personal Safari window")
local personalTarget, personalError = source.resolvePersonalSafariWindow({personalSafari})
assertEqual("ow_personal", personalTarget and personalTarget.id, "one Personal Safari target")
assertEqual(nil, personalError, "one Personal Safari target error")
assertEqual(false, source.isPersonalSafariWindow({
  app = {bundleId = "com.apple.Safari"},
  title = "Work — Inbox",
}), "Work is not Personal Safari")
personalTarget, personalError = source.resolvePersonalSafariWindow({})
assertEqual(nil, personalTarget, "absent Personal Safari target")
assertEqual(nil, personalError, "absent Personal Safari target error")
personalTarget, personalError = source.resolvePersonalSafariWindow({
  personalSafari,
  {
    id = "ow_personal_2",
    app = {bundleId = "com.apple.Safari"},
    title = "Personal — Second",
  },
})
assertEqual(nil, personalTarget, "ambiguous Personal Safari target")
assertEqual(
  "More than one Safari Personal window is managed by OmniWM",
  personalError,
  "ambiguous Personal Safari target error"
)

local workSafari = {
  id = "ow_work",
  app = {bundleId = "com.apple.Safari"},
  title = "Work — Inbox",
  workspace = {number = 9},
}
assertEqual(true, source.isWorkSafariWindow(workSafari), "Work Safari window")
local workTarget, workError = source.resolveWorkSafariWindow({workSafari})
assertEqual("ow_work", workTarget and workTarget.id, "one Work Safari target")
assertEqual(nil, workError, "one Work Safari target error")
assertEqual(false, source.isWorkSafariWindow({
  app = {bundleId = "com.apple.Safari"},
  title = "Personal — Inbox",
}), "Personal Safari window")
assertEqual(false, source.isWorkSafariWindow({
  app = {bundleId = "com.apple.Safari"},
  title = "",
}), "titleless Work Safari panel")
workTarget, workError = source.resolveWorkSafariWindow({})
assertEqual(nil, workTarget, "absent Work Safari target")
assertEqual(nil, workError, "absent Work Safari target error")
workTarget, workError = source.resolveWorkSafariWindow({
  workSafari,
  {
    id = "ow_work_2",
    app = {bundleId = "com.apple.Safari"},
    title = "Work — Second",
  },
})
assertEqual(nil, workTarget, "ambiguous Work Safari target")
assertEqual(
  "More than one Safari Work window is managed by OmniWM",
  workError,
  "ambiguous Work Safari target error"
)

local visibleGhostty = {
  {
    app = {bundleId = "com.mitchellh.ghostty"},
    workspace = {number = 3},
    isVisible = true,
  },
}
local hiddenGhostty = {
  {
    app = {bundleId = "com.mitchellh.ghostty"},
    workspace = {number = 2},
    isVisible = false,
  },
}
local ghosttyInWorkspace3 = {
  {
    app = {bundleId = "com.mitchellh.ghostty"},
    workspace = {number = 3},
    isVisible = true,
  },
}

local cases = {
  {"explicit Ghostty sender", true, "com.mitchellh.ghostty", 9, {}},
  {"explicit non-Ghostty sender", false, "com.tinyspeck.slackmacgap", 3, visibleGhostty},
  {"missing sender with visible Ghostty", true, nil, 3, visibleGhostty},
  {"Hammerspoon sender with visible Ghostty", true, "org.hammerspoon.Hammerspoon", 3, visibleGhostty},
  {"missing sender with hidden Ghostty", false, nil, 2, hiddenGhostty},
  {"missing sender with Ghostty in another workspace", false, nil, 2, ghosttyInWorkspace3},
}

for _, case in ipairs(cases) do
  local message, expected, senderBundle, activeWorkspace, windows = table.unpack(case)
  assertEqual(expected, route(senderBundle, activeWorkspace, windows), message)
end

local safariCases = {
  {
    "Safari browser window",
    true,
    {app = {bundleId = "com.apple.Safari"}, title = "Personal — Example"},
  },
  {
    "Safari titleless companion panel",
    false,
    {app = {bundleId = "com.apple.Safari"}, title = ""},
  },
  {
    "non-Safari window",
    false,
    {app = {bundleId = "com.mitchellh.ghostty"}, title = "Ghostty"},
  },
}

for _, case in ipairs(safariCases) do
  local message, expected, window = table.unpack(case)
  assertEqual(expected, isSafariBrowserWindow(window), message)
end

local developmentSafari = {
  id = "ow_development",
  app = {bundleId = "com.apple.Safari"},
  title = "Development — Example",
  workspace = {number = 1},
}
assertEqual(true, isDevelopmentSafariWindow(developmentSafari), "Development Safari window")
assertEqual(false, isDevelopmentSafariWindow({
  app = {bundleId = "com.apple.Safari"},
  title = "Personal — Example",
}), "Personal Safari window")
assertEqual(false, isDevelopmentSafariWindow({
  app = {bundleId = "com.apple.Safari"},
  title = "",
}), "titleless Safari panel")

local developmentTarget, developmentError = resolveDevelopmentSafariWindow({developmentSafari})
assertEqual("ow_development", developmentTarget and developmentTarget.id, "Development target across workspaces")
assertEqual(nil, developmentError, "Development target error")

developmentTarget, developmentError = resolveDevelopmentSafariWindow({})
assertEqual(nil, developmentTarget, "absent Development target")
assertEqual(nil, developmentError, "absent Development target error")

developmentTarget, developmentError = resolveDevelopmentSafariWindow({
  developmentSafari,
  {
    id = "ow_development_2",
    app = {bundleId = "com.apple.Safari"},
    title = "Development — Second",
    workspace = {number = 3},
  },
})
assertEqual(nil, developmentTarget, "ambiguous Development target")
assertEqual(
  "More than one Safari Development window is managed by OmniWM",
  developmentError,
  "ambiguous Development target error"
)

assertEqual(868906217, normalizeNativeWindowID("868906217"), "string native window ID")
assertEqual(868906217, normalizeNativeWindowID(868906217), "numeric native window ID")
assertEqual(nil, normalizeNativeWindowID(""), "empty native window ID")
assertEqual(nil, normalizeNativeWindowID("window"), "text native window ID")
assertEqual(nil, normalizeNativeWindowID(0), "zero native window ID")
assertEqual(nil, normalizeNativeWindowID(-1), "negative native window ID")
assertEqual(nil, normalizeNativeWindowID(1.5), "fractional native window ID")
assertEqual(nil, normalizeNativeWindowID("999999999999999999999"), "oversized native window ID")
assertEqual(nil, normalizeNativeWindowID(math.huge), "infinite native window ID")
assertEqual(nil, normalizeNativeWindowID(0 / 0), "NaN native window ID")

local function decodeTestWindowID(window)
  return tonumber(window.id and window.id:match("_(%d+)$"))
end

local nativeTarget, nativeError = resolveSafariWindowByNativeID({
  {id = "ow_105", app = {bundleId = "com.apple.Safari"}, title = "Personal — Example"},
}, 105, decodeTestWindowID)
assertEqual("ow_105", nativeTarget and nativeTarget.id, "Safari native ID target")
assertEqual(nil, nativeError, "Safari native ID target error")

nativeTarget, nativeError = resolveSafariWindowByNativeID({}, 105, decodeTestWindowID)
assertEqual(nil, nativeTarget, "absent Safari native ID target")
assertEqual("Could not find the Safari window that received the URL", nativeError, "absent Safari native ID error")

nativeTarget, nativeError = resolveSafariWindowByNativeID({
  {id = "ow_105", app = {bundleId = "com.apple.Safari"}, title = ""},
}, 105, decodeTestWindowID)
assertEqual(nil, nativeTarget, "titleless Safari native ID target")
assertEqual("Could not find the Safari window that received the URL", nativeError, "titleless Safari native ID error")

nativeTarget, nativeError = resolveSafariWindowByNativeID({
  {id = "ow_105", app = {bundleId = "com.apple.Safari"}, title = "Personal — One"},
  {id = "copy_105", app = {bundleId = "com.apple.Safari"}, title = "Personal — Two"},
}, 105, decodeTestWindowID)
assertEqual(nil, nativeTarget, "ambiguous Safari native ID target")
assertEqual("More than one Safari window matched the received URL", nativeError, "ambiguous Safari native ID error")

assertEqual(true, isChatGPTSender("com.openai.codex"), "ChatGPT sender")
assertEqual(false, isChatGPTSender("com.apple.Safari"), "non-ChatGPT sender")

local parsedHosts = {
  ["https://fastmail.com/mail"] = "fastmail.com",
  ["https://app.fastmail.com/mail"] = "app.fastmail.com",
  ["https://APP.FASTMAIL.COM/mail"] = "APP.FASTMAIL.COM",
  ["https://fastmail.com.example.test/"] = "fastmail.com.example.test",
  ["https://notfastmail.com/"] = "notfastmail.com",
  ["https://fastmail.com@other.test/mail"] = "other.test",
  ["https://other.test/fastmail.com"] = "other.test",
  ["invalid-url"] = false,
}
local function parseTestURL(url)
  return {host = parsedHosts[url]}
end
local destination = source.chatGPTDestination
assertEqual(
  "personal-safari",
  destination("com.openai.codex", "https://fastmail.com/mail", parseTestURL),
  "Fastmail apex"
)
assertEqual(
  "personal-safari",
  destination("com.openai.codex", "https://app.fastmail.com/mail", parseTestURL),
  "Fastmail subdomain"
)
assertEqual(
  "personal-safari",
  destination("com.openai.codex", "https://APP.FASTMAIL.COM/mail", parseTestURL),
  "case-insensitive Fastmail"
)
for _, url in ipairs({
  "https://fastmail.com.example.test/",
  "https://notfastmail.com/",
  "https://fastmail.com@other.test/mail",
  "https://other.test/fastmail.com",
  "invalid-url",
}) do
  assertEqual("chrome", destination("com.openai.codex", url, parseTestURL), "non-Fastmail URL: " .. url)
end
assertEqual(
  "chrome",
  destination("com.openai.codex", "https://fastmail.com", function() error("bad URL") end),
  "parser failure"
)
assertEqual(
  nil,
  destination("com.tinyspeck.slackmacgap", "https://fastmail.com/mail", parseTestURL),
  "other sender"
)

local chromeInWorkspace4 = {
  id = "ow_chrome",
  windowId = 42,
  app = {bundleId = "com.google.Chrome"},
  title = "ChatGPT",
  workspace = {number = 4},
}
local chromeInWorkspace2 = {
  id = "ow_personal_chrome",
  app = {bundleId = "com.google.Chrome"},
  title = "Personal",
  workspace = {number = 2},
}
local titlelessChrome = {
  id = "ow_chrome_panel",
  app = {bundleId = "com.google.Chrome"},
  title = "",
  workspace = {number = 4},
}

assertEqual(true, isChromeBrowserWindow(chromeInWorkspace4), "Chrome browser window")
assertEqual(false, isChromeBrowserWindow(titlelessChrome), "titleless Chrome panel")

local target, targetError = resolveActiveChromeWindow(4, {chromeInWorkspace4})
assertEqual("ow_chrome", target and target.id, "one Chrome target")
assertEqual(nil, targetError, "one Chrome target error")

target, targetError = resolveActiveChromeWindow(4, {})
assertEqual(nil, target, "absent Chrome target")
assertEqual(nil, targetError, "absent Chrome target error")

target, targetError = resolveActiveChromeWindow(4, {chromeInWorkspace2})
assertEqual(nil, target, "Chrome target in another workspace")
assertEqual(nil, targetError, "wrong-workspace target error")

target, targetError = resolveActiveChromeWindow(4, {titlelessChrome})
assertEqual(nil, target, "titleless Chrome target")
assertEqual(nil, targetError, "titleless Chrome target error")

local secondChrome = {
  id = "ow_chrome_2",
  windowId = 43,
  app = {bundleId = "com.google.Chrome"},
  title = "Second",
  workspace = {number = 4},
}
target, targetError = resolveActiveChromeWindow(4, {
  chromeInWorkspace4,
  secondChrome,
})
assertEqual(nil, target, "ambiguous Chrome target")
assertEqual(
  "More than one Chrome browser window is in the active workspace",
  targetError,
  "ambiguous Chrome target error"
)

target, targetError = resolveActiveChromeWindow(4, {
  chromeInWorkspace4,
  secondChrome,
}, 42)
assertEqual("ow_chrome", target and target.id, "preferred native Chrome target")
assertEqual(nil, targetError, "preferred native Chrome target error")

target, targetError = resolveActiveChromeWindow(4, {
  chromeInWorkspace4,
  secondChrome,
}, 999)
assertEqual(nil, target, "stale preferred Chrome target")
assertEqual(
  "More than one Chrome browser window is in the active workspace",
  targetError,
  "stale preferred Chrome target error"
)

local preferredApplication = {
  focusedWindow = function()
    return {id = function() return 42 end}
  end,
}
assertEqual(
  42,
  preferredChromeNativeWindowID(preferredApplication),
  "preferred Chrome native window ID"
)
assertEqual(nil, preferredChromeNativeWindowID(nil), "missing Chrome application")
assertEqual(
  nil,
  preferredChromeNativeWindowID({focusedWindow = function() return nil end}),
  "missing focused Chrome window"
)
assertEqual(
  nil,
  preferredChromeNativeWindowID({
    focusedWindow = function()
      return {id = function() return math.huge end}
    end,
  }),
  "invalid preferred Chrome native window ID"
)

if failures > 0 then
  os.exit(1)
end

print(string.format(
  "PASS: %d URL source cases, %d Safari cases, and ChatGPT Chrome cases",
  #cases,
  #safariCases
))
