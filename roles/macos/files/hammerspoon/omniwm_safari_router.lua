local M = {}

local function recover(deps, message)
  deps.notify(message)
  deps.focusSafari()
end

function M.route(url, deps)
  if not deps.openURL(url) then
    deps.notify("Could not open the URL in Safari")
    return
  end

  deps.after(function()
    local nativeID, idError = deps.frontWindowID()
    if idError or not nativeID then
      recover(deps, idError or "Could not resolve Safari's front window ID")
      return
    end

    deps.windows(function(windows, windowsError)
      if windowsError then
        recover(deps, windowsError)
        return
      end

      local target, resolveError = deps.resolve(windows, nativeID)
      if resolveError or not target then
        recover(deps, resolveError or "Could not resolve Safari's target window")
        return
      end

      deps.navigate(target.id, function(_, navigateError)
        if navigateError then
          recover(deps, navigateError)
          return
        end
        deps.confirmFocused(target.id, function(_, focusError)
          if focusError then
            recover(deps, focusError)
          end
        end)
      end)
    end)
  end)
end

return M
