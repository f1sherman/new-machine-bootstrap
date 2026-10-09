package.path = "roles/macos/files/hammerspoon/?.lua;" .. package.path
local recovery = require("omniwm_safari_recovery")

local function harness(options)
  options = options or {}
  local tasks, notifications = {}, {}
  local eventCallback
  local hs = {
    application = {watcher = {launched = 1, terminated = 2, activated = 3}},
    task = {},
  }
  hs.application.watcher.new = function(callback)
    eventCallback = callback
    return {start = function() end}
  end
  hs.task.new = function(path, callback, args)
    if options.createFailure then return nil end
    local task = {path = path, args = args, callback = callback}
    function task:start() return not options.startFailure end
    function task:terminate() self.terminated = true end
    tasks[#tasks + 1] = task
    return task
  end
  local controller = recovery.new(hs, function(message)
    notifications[#notifications + 1] = message
  end)
  return {
    controller = controller, tasks = tasks, notifications = notifications,
    event = function(event, bundle, pid)
      eventCallback("Safari", event, {
        bundleID = function() return bundle end,
        pid = function() return pid or (bundle == "com.apple.Safari" and 123 or 456) end,
      })
    end,
    launch = function()
      eventCallback("Safari", 1, {
        bundleID = function() return "com.apple.Safari" end,
        pid = function() return 123 end,
      })
    end,
  }
end

local h = harness()
assert(#h.tasks == 0, "initialization must not move windows")
h.event(3, "com.apple.Safari")
h.event(1, "com.google.Chrome")
assert(#h.tasks == 0, "activation and other apps must not trigger recovery")
h.launch()
assert(#h.tasks == 1, "Safari launch starts one recovery")
assert(h.tasks[1].path == os.getenv("HOME") .. "/.local/bin/recover-omniwm-workspaces")
assert(table.concat(h.tasks[1].args, " ") == "--bundle-id com.apple.Safari")
h.launch()
assert(#h.tasks == 1, "duplicate launch must not overlap recovery")
h.event(2, "com.google.Chrome")
assert(not h.tasks[1].terminated, "other app termination cannot cancel Safari recovery")
h.event(2, nil, 456)
assert(not h.tasks[1].terminated, "unrelated PID-only termination cannot cancel recovery")
h.event(2, nil, 123)
assert(h.tasks[1].terminated, "Safari termination cancels old recovery")
h.launch()
assert(#h.tasks == 2, "relaunch starts fresh recovery")
h.tasks[1].callback(15, "", "terminated")
h.launch()
assert(#h.tasks == 2, "old completion cannot clear new recovery")
assert(#h.notifications == 0, "cancelled task does not report spurious failure")
h.tasks[2].callback(0, "recovered", "")
h.launch()
assert(#h.tasks == 3, "completion permits a later launch")
h.tasks[3].callback(1, "", "IPC failed")
assert(h.notifications[1]:find("IPC failed", 1, true), "helper failure is reported")
h.launch()
assert(#h.tasks == 4, "failure permits a later launch")

for _, option in ipairs({"createFailure", "startFailure"}) do
  local broken = harness({[option] = true})
  broken.launch()
  broken.launch()
  assert(#broken.notifications == 2, "task failure reports and permits retry")
end

print("PASS: Safari restart recovery lifecycle")
