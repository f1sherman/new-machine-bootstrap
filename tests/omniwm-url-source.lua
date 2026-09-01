local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local source = require("omniwm_url_source")
local route = source.shouldRouteGhostty
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

if failures > 0 then
  os.exit(1)
end

print(string.format("PASS: %d OmniWM URL source cases", #cases))
