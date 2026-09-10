local M = {}

function M.new()
  local creationInProgress = false
  local downloads = {}

  function downloads.beginCreation(notify)
    if creationInProgress then
      notify("The Downloads window is still being created")
      return false
    end
    creationInProgress = true
    return true
  end

  function downloads.finishCreation()
    creationInProgress = false
  end

  function downloads.isFocused(window)
    return type(window) == "table" and window.isFocused == true
  end

  function downloads.shouldCreateAfterLock(scratchpad, actions)
    if #scratchpad == 0 then
      return true
    end

    if #scratchpad == 1 and actions.isFinder(scratchpad[1]) then
      actions.show(scratchpad[1].id)
    elseif #scratchpad > 1 then
      actions.notify("OmniWM returned more than one scratchpad window")
    else
      actions.notify("Another window owns the OmniWM scratchpad")
    end
    actions.done()
    return false
  end

  function downloads.recoverScratchpad(snapshot, actions)
    local navigated = false
    local complete = false
    local target

    local function finish(message)
      if complete then
        return
      end

      local function completeRecovery(restoreError)
        if complete then
          return
        end
        complete = true
        if restoreError then
          if message then
            message = tostring(message) .. "; " .. tostring(restoreError)
          else
            message = restoreError
          end
        end
        if message then
          actions.notify(message)
        end
        actions.done()
      end

      if not navigated then
        completeRecovery()
      elseif snapshot.focusedWindow and snapshot.focusedWindow.id then
        actions.restoreWindow(snapshot.focusedWindow.id, completeRecovery)
      elseif snapshot.activeWorkspace and snapshot.activeWorkspace.number then
        actions.restoreWorkspace(snapshot.activeWorkspace.number, completeRecovery)
      else
        completeRecovery()
      end
    end

    if #(snapshot.scratchpad or {}) ~= 0 then
      finish("Another window owns OmniWM scratchpad slot 1")
      return
    end

    local candidates = snapshot.downloadsWindows or {}
    if #candidates == 0 then
      finish()
      return
    elseif #candidates > 1 then
      finish("More than one Downloads Finder window is managed by OmniWM")
      return
    end
    target = candidates[1]

    navigated = true
    actions.navigate(target.id, function(_, navigateError)
      if navigateError then
        finish(navigateError)
        return
      end
      actions.confirmFocused(target.id, function(_, focusError)
        if focusError then
          finish(focusError)
          return
        end
        actions.assign(function(_, assignError)
          if assignError then
            finish(assignError)
            return
          end
          actions.confirmAssigned(target.id, function(assignedWindow, confirmError)
            if confirmError then
              finish(confirmError)
              return
            elseif type(assignedWindow) ~= "table" or assignedWindow.id ~= target.id then
              finish("Could not confirm the Downloads scratchpad assignment")
              return
            end
            if assignedWindow.isVisible then
              actions.hide(target.id, function(_, hideError)
                finish(hideError)
              end)
            else
              finish()
            end
          end)
        end)
      end)
    end)
  end

  function downloads.assignNewScratchpad(window, actions)
    local function finish(message)
      if message then
        actions.notify(message)
      end
      actions.done()
    end

    actions.queryScratchpad(function(scratchpad, scratchpadError)
      if scratchpadError then
        finish(scratchpadError)
        return
      end
      if #scratchpad == 1 and scratchpad[1].id == window.id then
        actions.show(window.id)
        finish()
        return
      end
      if #scratchpad ~= 0 then
        finish("A different window owns the OmniWM scratchpad")
        return
      end

      actions.queryTarget(window.id, function(target, targetError)
        if targetError then
          finish(targetError)
          return
        end
        if not downloads.isFocused(target) then
          finish("The new Downloads window lost focus. Try the shortcut again.")
          return
        end

        actions.assign(function(_, assignError)
          if assignError then
            finish(assignError)
            return
          end
          actions.show(window.id)
          finish()
        end)
      end)
    end)
  end

  return downloads
end

return M
