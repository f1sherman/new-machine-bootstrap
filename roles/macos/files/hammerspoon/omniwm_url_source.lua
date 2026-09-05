local M = {}
local chatGPTBundleID = "com.openai.codex"
local chromeBundleID = "com.google.Chrome"
local ghosttyBundleID = "com.mitchellh.ghostty"
local hammerspoonBundleID = "org.hammerspoon.Hammerspoon"

function M.isSafariBrowserWindow(window)
  return window.app
    and window.app.bundleId == "com.apple.Safari"
    and type(window.title) == "string"
    and window.title ~= ""
end

function M.isChatGPTSender(senderBundle)
  return senderBundle == chatGPTBundleID
end

function M.isChromeBrowserWindow(window)
  return window.app
    and window.app.bundleId == chromeBundleID
    and type(window.title) == "string"
    and window.title ~= ""
end

function M.resolveActiveChromeWindow(activeWorkspace, windows)
  local candidates = {}
  for _, window in ipairs(windows or {}) do
    if M.isChromeBrowserWindow(window)
      and window.workspace
      and window.workspace.number == activeWorkspace then
      table.insert(candidates, window)
    end
  end

  if #candidates == 1 then
    return candidates[1], nil
  elseif #candidates > 1 then
    return nil, "More than one Chrome browser window is in the active workspace"
  end
  return nil, nil
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
