local M = {}

function M.new(hs, notify)
  local state = {}
  local helper = os.getenv("HOME") .. "/.local/bin/recover-omniwm-workspaces"
  state.watcher = hs.application.watcher.new(function(_, event, app)
    if not app or app:bundleID() ~= "com.apple.Safari" then
      return
    end
    if event == hs.application.watcher.terminated then
      local task = state.task
      state.task = nil
      if task then task:terminate() end
      return
    end
    if event ~= hs.application.watcher.launched or state.task then
      return
    end

    local task
    task = hs.task.new(helper, function(exitCode, stdout, stderr)
      if state.task ~= task then return end
      state.task = nil
      if exitCode ~= 0 then
        local detail = (stderr ~= "" and stderr or stdout):gsub("%s+$", "")
        notify("Safari workspace recovery failed: " .. detail)
      end
    end, {"--bundle-id", "com.apple.Safari"})
    if not task then
      notify("Could not create Safari workspace recovery task")
      return
    end
    state.task = task
    if not task:start() then
      state.task = nil
      notify("Could not start Safari workspace recovery task")
    end
  end)
  state.watcher:start()
  return state
end

return M
