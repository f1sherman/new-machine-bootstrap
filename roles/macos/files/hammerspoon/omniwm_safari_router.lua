local M = {}

local function recover(deps, message)
  deps.notify(message)
  deps.focusSafari()
end

local function resolveTarget(deps, callback)
  deps.poll(function(done)
    local nativeID = deps.frontWindowID()
    if not nativeID then
      done(false, nil)
      return
    end

    deps.windows(function(windows, windowsError)
      if windowsError then
        done(false, nil)
        return
      end
      local target = deps.resolve(windows, nativeID)
      done(target or false, nil)
    end)
  end, callback)
end

function M.route(url, deps)
  if not deps.openURL(url) then
    deps.notify("Could not open the URL in Safari")
    return
  end

  deps.delay(function()
    resolveTarget(deps, function(target, resolveError)
      if resolveError or not target then
        recover(deps, resolveError or "Could not resolve Safari's target window")
        return
      end

      deps.navigate(target.id, function(_, navigateError)
        if navigateError then
          recover(deps, navigateError)
          return
        end
        deps.pollFocused(target.id, function(_, focusError)
          if focusError then
            recover(deps, focusError)
          end
        end)
      end)
    end)
  end)
end

return M
