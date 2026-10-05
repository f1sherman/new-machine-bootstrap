local sourcePath = "roles/macos/files/hammerspoon/?.lua"
package.path = sourcePath .. ";" .. package.path

local photos = require("omniwm_photos")
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

local function window(id, workspace, visible)
  return {
    id = id,
    isVisible = visible,
    workspace = {number = workspace},
  }
end

local function harness(options)
  local calls = {focus = {}, summon = {}, query = 0, completions = {}}
  local actions = {
    focus = function(id, callback)
      table.insert(calls.focus, id)
      callback(nil, options.focusError)
    end,
    summon = function(id, callback)
      table.insert(calls.summon, id)
      local index = #calls.summon
      callback(nil, options.summonErrors and options.summonErrors[index])
    end,
    queryPhotos = function(callback)
      calls.query = calls.query + 1
      callback(options.replacements, options.queryError)
    end,
  }

  photos.show(options.target, {number = options.activeWorkspace or 4}, actions,
    function(_, showError)
      table.insert(calls.completions, showError or false)
    end)
  return calls
end

local visible = harness({target = window("visible", 2, true)})
assertEqual("visible", visible.focus[1], "visible window receives exact focus")
assertEqual(0, #visible.summon, "visible window is not summoned")

local localWindow = harness({target = window("local", 4, false)})
assertEqual("local", localWindow.focus[1], "local hidden window receives exact focus")
assertEqual(0, #localWindow.summon, "local window is not summoned")

local remote = harness({target = window("remote", 2, false)})
assertEqual("remote", remote.summon[1], "remote window is summoned")
assertEqual("remote", remote.focus[1], "summoned window receives exact focus")

local replacement = harness({
  target = window("stale", 2, false),
  summonErrors = {"omniwmctl window summon-right failed: error: not_found"},
  replacements = {window("fresh", 4, true)},
})
assertEqual("stale", replacement.summon[1], "stale exact ID is attempted once")
assertEqual(1, replacement.query, "missing exact ID triggers one fresh query")
assertEqual("fresh", replacement.focus[1], "fresh exact ID receives focus")
assertEqual(false, replacement.completions[1], "fresh replacement succeeds")

local absent = harness({
  target = window("stale", 2, false),
  summonErrors = {"omniwmctl window summon-right failed: error: not_found"},
  replacements = {},
})
assertEqual(1, absent.query, "absent replacement is queried once")
assertEqual("Photos no longer has a managed window", absent.completions[1],
  "absent replacement stops safely")

local ambiguous = harness({
  target = window("stale", 2, false),
  summonErrors = {"omniwmctl window summon-right failed: error: not_found"},
  replacements = {window("one", 2, false), window("two", 3, false)},
})
assertEqual("More than one Photos window is managed by OmniWM", ambiguous.completions[1],
  "ambiguous replacement stops safely")

local unrelated = harness({
  target = window("remote", 2, false),
  summonErrors = {"IPC unavailable"},
  replacements = {window("fresh", 4, true)},
})
assertEqual(0, unrelated.query, "unrelated error does not refresh")
assertEqual("IPC unavailable", unrelated.completions[1], "unrelated error is preserved")

local secondFailure = harness({
  target = window("stale", 2, false),
  summonErrors = {
    "omniwmctl window summon-right failed: error: not_found",
    "omniwmctl window summon-right failed: error: not_found",
  },
  replacements = {window("fresh", 2, false)},
})
assertEqual(2, #secondFailure.summon, "fresh remote ID is attempted once")
assertEqual(1, secondFailure.query, "second missing ID does not loop")
assertEqual(
  "omniwmctl window summon-right failed: error: not_found",
  secondFailure.completions[1],
  "second failure is reported"
)

if failures > 0 then
  os.exit(1)
end

print("PASS: OmniWM Photos routing")
