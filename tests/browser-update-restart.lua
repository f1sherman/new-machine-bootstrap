local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local browserRestart = require("browser_update_restart")
local failures = 0

local function assertEqual(expected, actual, message)
  if expected ~= actual then
    failures = failures + 1
    io.stderr:write(string.format(
      "FAIL: %s (expected %s, got %s)\n",
      message,
      tostring(expected),
      tostring(actual)
    ))
  end
end

local function newHarness()
  local applications = {}
  local clock = 100
  local events = {quit = {}, launch = {}, error = {}}
  local polls = {}
  local scheduled = {count = 0}
  local quitResults = {}
  local launchResults = {}

  local dependencies = {
    scheduleAt = function(time, interval, callback)
      scheduled.count = scheduled.count + 1
      scheduled.time = time
      scheduled.interval = interval
      scheduled.callback = callback
      scheduled.timer = {kind = "daily"}
      return scheduled.timer
    end,
    doEvery = function(seconds, callback)
      local timer = {seconds = seconds, callback = callback, stopped = false}
      function timer:stop()
        self.stopped = true
      end
      table.insert(polls, timer)
      return timer
    end,
    find = function(bundleID)
      return applications[bundleID]
    end,
    quit = function(app)
      table.insert(events.quit, app.bundleID)
      return quitResults[app.bundleID] ~= false
    end,
    launch = function(bundleID)
      table.insert(events.launch, bundleID)
      return launchResults[bundleID] ~= false
    end,
    now = function()
      return clock
    end,
    logError = function(message)
      table.insert(events.error, message)
    end,
  }

  return {
    applications = applications,
    controller = browserRestart.new(dependencies),
    events = events,
    launchResults = launchResults,
    polls = polls,
    quitResults = quitResults,
    scheduled = scheduled,
    setClock = function(value)
      clock = value
    end,
  }
end

local scheduleHarness = newHarness()
local dailyTimer = scheduleHarness.controller.start()
assertEqual("04:00", scheduleHarness.scheduled.time, "daily restart time")
assertEqual("1d", scheduleHarness.scheduled.interval, "daily restart interval")
assertEqual(
  dailyTimer,
  scheduleHarness.scheduled.timer,
  "start returns retained daily timer"
)
assertEqual(
  dailyTimer,
  scheduleHarness.controller.start(),
  "repeated start returns the daily timer"
)
assertEqual(1, scheduleHarness.scheduled.count, "daily restart is scheduled once")
scheduleHarness.scheduled.callback()
assertEqual(0, #scheduleHarness.events.quit, "absent browsers are not quit")
assertEqual(0, #scheduleHarness.events.launch, "absent browsers are not launched")

local successHarness = newHarness()
successHarness.applications["com.brave.Browser"] = {
  bundleID = "com.brave.Browser",
}
successHarness.controller.runNow()
assertEqual(
  "com.brave.Browser",
  successHarness.events.quit[1],
  "running Brave quits normally"
)
assertEqual(1, successHarness.polls[1].seconds, "browser exit is polled each second")
successHarness.polls[1].callback()
assertEqual(0, #successHarness.events.launch, "running Brave is not launched before exit")
successHarness.applications["com.brave.Browser"] = nil
successHarness.polls[1].callback()
assertEqual(
  "com.brave.Browser",
  successHarness.events.launch[1],
  "stopped Brave relaunches"
)
assertEqual(true, successHarness.polls[1].stopped, "successful poll stops")

local quitFailureHarness = newHarness()
quitFailureHarness.applications["com.google.Chrome"] = {
  bundleID = "com.google.Chrome",
}
quitFailureHarness.quitResults["com.google.Chrome"] = false
quitFailureHarness.controller.runNow()
assertEqual(0, #quitFailureHarness.polls, "failed quit creates no poll")
assertEqual(0, #quitFailureHarness.events.launch, "failed quit does not relaunch")
assertEqual(1, #quitFailureHarness.events.error, "failed quit logs one error")

local launchFailureHarness = newHarness()
launchFailureHarness.applications["com.brave.Browser"] = {
  bundleID = "com.brave.Browser",
}
launchFailureHarness.launchResults["com.brave.Browser"] = false
launchFailureHarness.controller.runNow()
launchFailureHarness.applications["com.brave.Browser"] = nil
launchFailureHarness.polls[1].callback()
assertEqual(1, #launchFailureHarness.events.error, "failed relaunch logs one error")

local independentHarness = newHarness()
independentHarness.applications["com.brave.Browser"] = {
  bundleID = "com.brave.Browser",
}
independentHarness.applications["com.google.Chrome"] = {
  bundleID = "com.google.Chrome",
}
independentHarness.controller.runNow()
assertEqual(2, #independentHarness.polls, "browsers use independent polls")
independentHarness.applications["com.brave.Browser"] = nil
independentHarness.setClock(160)
independentHarness.polls[1].callback()
independentHarness.polls[2].callback()
assertEqual(
  "com.brave.Browser",
  independentHarness.events.launch[1],
  "Brave can relaunch while Chrome remains running"
)
assertEqual(true, independentHarness.polls[1].stopped, "completed Brave poll stops")
assertEqual(true, independentHarness.polls[2].stopped, "timed-out Chrome poll stops")
assertEqual(1, #independentHarness.events.launch, "timeout does not relaunch Chrome")
assertEqual(1, #independentHarness.events.error, "timeout logs one error")

local weakTimer = setmetatable({}, {__mode = "v"})
local retainedController = browserRestart.start({
  scheduleAt = function()
    local timer = {kind = "module-retained-daily"}
    weakTimer.daily = timer
    return timer
  end,
  doEvery = function()
    error("polling must not start during scheduler setup")
  end,
  find = function()
    return nil
  end,
  quit = function()
    error("quit must not run during scheduler setup")
  end,
  launch = function()
    error("launch must not run during scheduler setup")
  end,
  now = function()
    return 0
  end,
  logError = function()
    error("logging must not run during scheduler setup")
  end,
})
retainedController = nil
collectgarbage("collect")
collectgarbage("collect")
assertEqual(
  true,
  weakTimer.daily ~= nil,
  "module retains the started controller and its daily timer"
)

if failures > 0 then
  os.exit(1)
end

print("PASS: Hammerspoon browser update restart scheduling and state")
