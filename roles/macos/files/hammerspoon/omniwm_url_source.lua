local M = {}
local ghosttyBundleID = "com.mitchellh.ghostty"
local hammerspoonBundleID = "org.hammerspoon.Hammerspoon"

function M.isSafariBrowserWindow(window)
  return window.app
    and window.app.bundleId == "com.apple.Safari"
    and type(window.title) == "string"
    and window.title ~= ""
end

function M.shouldRouteGhostty(senderBundle, activeWorkspace, windows)
  if senderBundle == ghosttyBundleID then
    return true
  end
  if senderBundle ~= nil and senderBundle ~= hammerspoonBundleID then
    return false
  end

  for _, window in ipairs(windows or {}) do
    if window.app
      and window.app.bundleId == ghosttyBundleID
      and window.workspace
      and window.workspace.number == activeWorkspace
      and window.isVisible == true then
      return true
    end
  end
  return false
end

return M
