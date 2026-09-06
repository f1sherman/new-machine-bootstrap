local M = {}

function M.open(url, bundleID, browserName, deps)
  if not deps.openURL(url, bundleID) then
    deps.notify("Could not open the URL in " .. browserName)
    return false
  end
  if not deps.focus(bundleID) then
    deps.notify("Could not focus " .. browserName)
    return false
  end
  return true
end

return M
