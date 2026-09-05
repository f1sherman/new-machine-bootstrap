local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local source = require("omniwm_url_source")
local route = source.shouldRouteGhostty
local isSafariBrowserWindow = source.isSafariBrowserWindow
local isChatGPTSender = source.isChatGPTSender
local isChromeBrowserWindow = source.isChromeBrowserWindow
local resolveActiveChromeWindow = source.resolveActiveChromeWindow
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

assertEqual(true, isChatGPTSender("com.openai.codex"), "ChatGPT sender")
assertEqual(false, isChatGPTSender("com.apple.Safari"), "non-ChatGPT sender")

local chromeInWorkspace4 = {
  id = "ow_chrome",
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

target, targetError = resolveActiveChromeWindow(4, {
  chromeInWorkspace4,
  {
    id = "ow_chrome_2",
    app = {bundleId = "com.google.Chrome"},
    title = "Second",
    workspace = {number = 4},
  },
})
assertEqual(nil, target, "ambiguous Chrome target")
assertEqual(
  "More than one Chrome browser window is in the active workspace",
  targetError,
  "ambiguous Chrome target error"
)

if failures > 0 then
  os.exit(1)
end

print(string.format(
  "PASS: %d URL source cases, %d Safari cases, and ChatGPT Chrome cases",
  #cases,
  #safariCases
))
