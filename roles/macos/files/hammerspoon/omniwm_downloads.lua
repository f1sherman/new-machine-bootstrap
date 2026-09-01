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
