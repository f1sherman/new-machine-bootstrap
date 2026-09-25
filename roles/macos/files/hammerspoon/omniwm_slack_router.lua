local M = {}

function M.route(url, target, deps)
  if not target then
    if deps.createTarget then
      deps.createTarget(function(createdTarget, createError)
        if createError or not createdTarget then
          deps.notify(createError or deps.openError or "Could not create the Safari window")
          return
        end
        M.route(url, createdTarget, deps)
      end)
    elseif deps.failClosed then
      deps.notify(deps.openError or "Could not open the Safari link in its profile")
    else
      deps.fallback(url)
    end
    return
  end

  local created, createError = deps.openTab(target, url)
  if not created then
    deps.notify(
      createError
        or deps.openError
        or "Could not open the Slack link in Work Safari"
    )
    if not deps.failClosed then
      deps.fallback(url)
    end
    return
  end

  if createError then
    deps.notify(createError)
  end
  deps.navigate(target.id, function(_, navigateError)
    if navigateError then
      deps.notify(navigateError)
    end
  end)
end

return M
