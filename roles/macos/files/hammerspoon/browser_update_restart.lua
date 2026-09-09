local M = {}
local browsers = {
  {name = "Brave Browser", bundleID = "com.brave.Browser"},
  {name = "Google Chrome", bundleID = "com.google.Chrome"},
}
local timeoutSeconds = 60
local pollSeconds = 1

local function defaultDependencies()
  local logger = hs.logger.new("browser-update-restart", "info")
  return {
    scheduleAt = hs.timer.doAt,
    doEvery = hs.timer.doEvery,
    find = hs.application.get,
    quit = function(app)
      local ok, result = pcall(function()
        return app:kill()
      end)
      return ok and result ~= false
    end,
    launch = hs.application.launchOrFocusByBundleID,
    now = hs.timer.secondsSinceEpoch,
    logError = function(message)
      logger.e(message)
    end,
  }
end

function M.new(dependencies)
  dependencies = dependencies or defaultDependencies()
  local controller = {}
  local dailyTimer
  local pollTimers = {}

  local function stopPoll(timer)
    timer:stop()
    pollTimers[timer] = nil
  end

  local function restart(browser)
    local app = dependencies.find(browser.bundleID)
    if not app then
      return
    end

    if not dependencies.quit(app) then
      dependencies.logError("Could not quit " .. browser.name .. " for update restart")
      return
    end

    local deadline = dependencies.now() + timeoutSeconds
    local pollTimer
    pollTimer = dependencies.doEvery(pollSeconds, function()
      if not dependencies.find(browser.bundleID) then
        stopPoll(pollTimer)
        if not dependencies.launch(browser.bundleID) then
          dependencies.logError("Could not relaunch " .. browser.name .. " after update restart")
        end
      elseif dependencies.now() >= deadline then
        stopPoll(pollTimer)
        dependencies.logError("Timed out waiting for " .. browser.name .. " to quit")
      end
    end)
    pollTimers[pollTimer] = true
  end

  function controller.runNow()
    for _, browser in ipairs(browsers) do
      restart(browser)
    end
  end

  function controller.start()
    if not dailyTimer then
      dailyTimer = dependencies.scheduleAt("04:00", "1d", controller.runNow)
    end
    return dailyTimer
  end

  return controller
end

return M
