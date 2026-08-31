local failures = 0

local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL: " .. message .. "\n")
end

local function assertEqual(expected, actual, message)
  if expected ~= actual then
    fail(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
  end
end

local function assertTrue(value, message)
  if not value then fail(message) end
end

local function assertContains(value, fragment, message)
  if not value:find(fragment, 1, true) then
    fail(message .. " (missing " .. fragment .. ")")
  end
end

local panel = {visible = false}
local panelMethods = {
  "windowStyle", "level", "behaviorAsLabels", "windowTitle", "allowNewWindows",
}
for _, method in ipairs(panelMethods) do
  panel[method] = function(self, value)
    self[method .. "Value"] = value
    return self
  end
end
function panel:frame(value)
  if value then
    self.frameValue = value
    return self
  end
  return self.frameValue
end
function panel:html(value)
  self.htmlValue = value
  return self
end
function panel:show()
  self.visible = true
  return self
end
function panel:hide()
  self.visible = false
  return self
end
function panel:isVisible()
  return self.visible
end

local escapeHotkey = {enabled = false}
function escapeHotkey:enable()
  self.enabled = true
  return self
end
function escapeHotkey:disable()
  self.enabled = false
  return self
end
function escapeHotkey:trigger()
  self.callback()
end

local screenFrame = {x = 100, y = 50, w = 1000, h = 800}
local screen = {
  frame = function() return screenFrame end,
}
local currentScreen = screen
local webviewPreferences
local hsStub = {
  webview = {
    new = function(frame, preferences)
      panel.frameValue = frame
      webviewPreferences = preferences
      return panel
    end,
  },
  hotkey = {
    new = function(modifiers, key, callback)
      assertEqual(0, #modifiers, "Escape hotkey has no modifiers")
      assertEqual("escape", key, "Escape hotkey uses Escape")
      escapeHotkey.callback = callback
      return escapeHotkey
    end,
  },
  mouse = {
    getCurrentScreen = function() return currentScreen end,
  },
  drawing = {
    windowLevels = {floating = 9},
  },
}

local notifications = {}
local markdownPath = os.tmpname()
local function writeMarkdown(value)
  local file = assert(io.open(markdownPath, "w"))
  file:write(value)
  file:close()
end

writeMarkdown([[# Help
<script>&"'
]])

local module = dofile("roles/macos/files/hammerspoon/omniwm_cheatsheet.lua")
local controller = module.new({
  hs = hsStub,
  path = markdownPath,
  notify = function(message) table.insert(notifications, message) end,
})

controller:show()
assertTrue(panel.visible, "show displays the panel")
assertTrue(escapeHotkey.enabled, "show enables Escape")
assertEqual(false, webviewPreferences.javaScriptEnabled, "JavaScript is disabled")
assertEqual(false, webviewPreferences.javaScriptCanOpenWindowsAutomatically,
  "automatic JavaScript windows are disabled")
assertEqual(false, panel.allowNewWindowsValue, "new windows are disabled")
assertEqual(9, panel.levelValue, "panel uses the floating level")
assertEqual("OmniWM Cheat Sheet", panel.windowTitleValue, "panel has the managed title")
assertEqual("utility", panel.windowStyleValue[3], "panel uses utility style")
assertEqual("canJoinAllSpaces", panel.behaviorAsLabelsValue[1],
  "panel joins all Spaces")
assertEqual("fullScreenAuxiliary", panel.behaviorAsLabelsValue[2],
  "panel supports full-screen Spaces")
assertEqual(260, panel.frameValue.x, "panel is horizontally centered")
assertEqual(138, panel.frameValue.y, "panel is vertically centered")
assertEqual(680, panel.frameValue.w, "panel width is based on usable screen")
assertEqual(624, panel.frameValue.h, "panel height is based on usable screen")
assertContains(panel.htmlValue, "default-src 'none'", "HTML has a restrictive CSP")
assertContains(panel.htmlValue, "&lt;script&gt;&amp;&quot;&#39;", "Markdown is HTML escaped")

controller:toggle()
assertEqual(false, panel.visible, "toggle hides a visible panel")
assertEqual(false, escapeHotkey.enabled, "hide disables Escape")

writeMarkdown("second version")
screenFrame = {x = 0, y = 0, w = 800, h = 600}
controller:show()
assertContains(panel.htmlValue, "second version", "show reloads Markdown from disk")
assertEqual(128, panel.frameValue.x, "each show recenters on the current screen")
assertEqual(60, panel.frameValue.y, "each show recenters within the usable frame")
escapeHotkey:trigger()
assertEqual(false, panel.visible, "Escape hides the panel")
assertEqual(false, escapeHotkey.enabled, "Escape disables itself after hiding")

os.remove(markdownPath)
controller:show()
assertEqual(false, panel.visible, "read failure keeps the panel hidden")
assertEqual(false, escapeHotkey.enabled, "read failure keeps Escape disabled")
assertEqual(1, #notifications, "read failure sends one notification")
assertContains(notifications[1], "Could not read OmniWM cheat sheet",
  "read failure notification has context")

writeMarkdown("restored")
currentScreen = nil
controller:show()
assertEqual(false, panel.visible, "missing screen keeps the panel hidden")
assertEqual(false, escapeHotkey.enabled, "missing screen keeps Escape disabled")
assertEqual(2, #notifications, "missing screen sends one notification")
assertContains(notifications[2], "Could not find the current display",
  "missing screen notification has context")
os.remove(markdownPath)

if failures > 0 then
  os.exit(1)
end
print("OmniWM cheat-sheet panel tests passed")
