local M = {}

function M.route(window, url, deps)
  deps.focus(window.id, function(_, focusError)
    if focusError then
      deps.notify(focusError)
      deps.fallback(url)
      return
    end

    local chromeWindowID, idError = deps.frontWindowID()
    if idError or not chromeWindowID then
      deps.notify(idError or "Could not resolve the focused Chrome window ID")
      deps.fallback(url)
      return
    end

    deps.confirmFocused(window.id, function(_, confirmError)
      if confirmError then
        deps.notify(confirmError)
        deps.fallback(url)
        return
      end

      local created, createError = deps.createTab(chromeWindowID, url)
      if createError then
        deps.notify(createError)
      end
      if not created then
        deps.fallback(url)
        return
      end

      deps.focus(window.id, function(_, finalFocusError)
        if finalFocusError then
          deps.notify(finalFocusError)
        end
      end)
    end)
  end)
end

return M
