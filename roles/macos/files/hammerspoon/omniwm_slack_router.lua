local M = {}

function M.route(url, target, deps)
  if not target then
    deps.fallback(url)
    return
  end

  local created, createError = deps.openTab(target, url)
  if not created then
    deps.notify(createError or "Could not open the Slack link in Work Safari")
    deps.fallback(url)
    return
  end

  deps.navigate(target.id, function(_, navigateError)
    if navigateError then
      deps.notify(navigateError)
    end
  end)
end

return M
