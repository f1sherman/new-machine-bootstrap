local M = {}

function M.new(hs, notify)
  local state = {}
  local helper = os.getenv("HOME") .. "/.local/bin/recover-omniwm-workspaces"
  state.watcher = hs.application.watcher.new(function(_, event, app)
    if not app then return end
    -- Terminated applications only guarantee a PID, not a bundle ID.
    if event == hs.application.watcher.terminated then
      if app:pid() == state.pid then
        local task = state.task
        state.task = nil
        state.pid = nil
        if task then task:terminate() end
      end
      return
    end
    if event ~= hs.application.watcher.launched
      or app:bundleID() ~= "com.apple.Safari" or state.task then
      return
    end

    state.pid = app:pid()
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
