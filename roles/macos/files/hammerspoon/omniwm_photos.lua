local M = {}

local function workspaceNumber(window)
  return window and window.workspace and window.workspace.number
end

local function isMissingWindowError(message)
  return type(message) == "string"
    and message:match("error:%s*not_found%s*$") ~= nil
end

local function showCurrent(window, activeWorkspace, actions, allowRefresh, callback)
  if window.isVisible == true
    or workspaceNumber(window) == activeWorkspace.number then
    actions.focus(window.id, callback)
    return
  end

  actions.summon(window.id, function(_, summonError)
    if not summonError then
      actions.focus(window.id, callback)
      return
    end
    if not allowRefresh or not isMissingWindowError(summonError) then
      callback(nil, summonError)
      return
    end

    actions.queryPhotos(function(windows, queryError)
      if queryError then
        callback(nil, queryError)
      elseif #windows == 0 then
        callback(nil, "Photos no longer has a managed window")
      elseif #windows > 1 then
        callback(nil, "More than one Photos window is managed by OmniWM")
      else
        showCurrent(windows[1], activeWorkspace, actions, false, callback)
      end
    end)
  end)
end

function M.show(window, activeWorkspace, actions, callback)
  showCurrent(window, activeWorkspace, actions, true, callback)
end

return M
