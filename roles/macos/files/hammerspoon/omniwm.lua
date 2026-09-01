local M = {}
local cheatsheetPanel = require("omniwm_cheatsheet").new()
local downloads = require("omniwm_downloads").new()
local urlSource = require("omniwm_url_source")
local omniwmctl = os.getenv("HOME") .. "/.local/bin/omniwmctl"
local logger = hs.logger.new("omniwm", "info")
local runningTasks = {}
local dedicatedSafariWindowKey = "omniwmDedicatedSafariWindowId"

local function copyArray(values)
  local result = {}
  for index, value in ipairs(values) do
    result[index] = value
  end
  return result
end

local function windowList(document)
  local result = document and document.result
  local payload = result and result.payload
  local windows = payload and payload.windows
  if type(windows) ~= "table" then
    return nil, "OmniWM returned an invalid window list"
  end
  return windows, nil
end

local function bundleID(window)
  return window and window.app and window.app.bundleId
end

local function workspaceNumber(window)
  return window and window.workspace and window.workspace.number
end

local function findWindows(windows, predicate)
  local matches = {}
  for _, window in ipairs(windows) do
    if predicate(window) then
      table.insert(matches, window)
    end
  end
  return matches
end

local function findWindowByID(windows, id)
  for _, window in ipairs(windows) do
    if window.id == id then
      return window
    end
  end
  return nil
end

local function appleScriptLiteral(value)
  local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"')
  escaped = escaped:gsub("\r", "\\r"):gsub("\n", "\\n")
  return '"' .. escaped .. '"'
end

function M.notify(message)
  hs.notify.new({title = "OmniWM", informativeText = tostring(message)}):send()
end

function M.run(args, callback)
  callback = callback or function() end
  local task
  task = hs.task.new(omniwmctl, function(exitCode, stdout, stderr)
    runningTasks[task] = nil
    if exitCode ~= 0 then
      local detail = (stderr ~= "" and stderr or stdout):gsub("%s+$", "")
      local operation = args[1] or "command"
      if args[1] == "window" and args[2] then
        operation = operation .. " " .. args[2]
      elseif args[1] == "command" and args[2] then
        operation = operation .. " " .. args[2]
      elseif args[1] == "query" and args[2] then
        operation = operation .. " " .. args[2]
      end
      logger.ef("omniwmctl %s failed: %s; args=%s", operation, detail, hs.inspect(args))
      callback(nil, "omniwmctl " .. operation .. " failed: " .. detail)
      return
    end
    callback(stdout, nil)
  end, copyArray(args))

  if not task then
    callback(nil, "Could not create omniwmctl task")
    return
  end

  runningTasks[task] = true
  if not task:start() then
    runningTasks[task] = nil
    callback(nil, "Could not start omniwmctl task")
  end
end

function M.query(args, callback)
  local queryArgs = copyArray(args)
  table.insert(queryArgs, "--format")
  table.insert(queryArgs, "json")
  M.run(queryArgs, function(stdout, runError)
    if runError then
      callback(nil, runError)
      return
    end

    local decodedOK, decoded = pcall(hs.json.decode, stdout)
    if not decodedOK or type(decoded) ~= "table" then
      callback(nil, "OmniWM returned malformed JSON")
      return
    end
    if decoded.ok == false then
      callback(nil, decoded.error or "OmniWM query failed")
      return
    end
    callback(decoded, nil)
  end)
end

function M.poll(predicate, timeoutSeconds, callback)
  local deadline = hs.timer.secondsSinceEpoch() + timeoutSeconds
  local complete = false
  local inFlight = false
  local timer

  local function finish(result, pollError)
    if complete then
      return
    end
    complete = true
    if timer then
      timer:stop()
    end
    callback(result, pollError)
  end

  timer = hs.timer.doUntil(function()
    if not complete and hs.timer.secondsSinceEpoch() >= deadline then
      finish(nil, "Timed out while waiting for OmniWM")
    end
    return complete
  end, function()
    if inFlight or complete then
      return
    end
    inFlight = true
    predicate(function(result, predicateError)
      inFlight = false
      if predicateError then
        finish(nil, predicateError)
      elseif result then
        finish(result, nil)
      end
    end)
  end, 0.1)
end

function M.activeWorkspace(callback)
  M.query({"query", "active-workspace"}, function(document, queryError)
    if queryError then
      callback(nil, queryError)
      return
    end
    local workspace = document.result and document.result.payload and document.result.payload.workspace
    if type(workspace) ~= "table" or type(workspace.number) ~= "number" then
      callback(nil, "OmniWM returned an invalid active workspace")
      return
    end
    callback(workspace, nil)
  end)
end

function M.windows(callback)
  M.query({"query", "windows"}, function(document, queryError)
    if queryError then
      callback(nil, queryError)
      return
    end
    local windows, listError = windowList(document)
    callback(windows, listError)
  end)
end

function M.reportResult(_, operationError)
  if operationError then
    M.notify(operationError)
  end
end

local function queryWindows(arguments, callback)
  local args = {"query", "windows"}
  for _, argument in ipairs(arguments) do
    table.insert(args, argument)
  end
  M.query(args, function(document, queryError)
    if queryError then
      callback(nil, queryError)
      return
    end
    local windows, listError = windowList(document)
    callback(windows, listError)
  end)
end

local function pollWindow(id, predicate, callback)
  M.poll(function(done)
    queryWindows({"--window", id}, function(windows, queryError)
      if queryError then
        done(nil, queryError)
        return
      end
      local window = findWindowByID(windows, id)
      done(window and predicate(window) and window or false, nil)
    end)
  end, 5, callback)
end

local function focusSummonedWindow(id, callback)
  M.poll(function(done)
    M.run({"window", "focus", id}, function()
      queryWindows({"--window", id}, function(windows, queryError)
        if queryError then
          done(nil, queryError)
          return
        end
        local window = findWindowByID(windows, id)
        done(window and window.isFocused == true and window or false, nil)
      end)
    end)
  end, 5, callback)
end

local function pollNewWindow(bundle, previousIDs, callback, predicate)
  M.poll(function(done)
    M.windows(function(windows, queryError)
      if queryError then
        done(nil, queryError)
        return
      end
      local candidates = findWindows(windows, function(window)
        return bundleID(window) == bundle
          and not previousIDs[window.id]
          and (not predicate or predicate(window))
      end)
      if #candidates > 1 then
        done(nil, "More than one new window appeared")
      elseif #candidates == 1 then
        done(candidates[1], nil)
      else
        done(false, nil)
      end
    end)
  end, 5, callback)
end

local function focusVisibleScratchpad(id)
  pollWindow(id, function(window)
    return window.isVisible == true
  end, function(_, visibilityError)
    if visibilityError then
      M.notify(visibilityError)
      return
    end
    focusSummonedWindow(id, function(_, focusError)
      if focusError then
        M.notify(focusError)
      end
    end)
  end)
end

local function showScratchpadIfHidden(id)
  M.poll(function(done)
    queryWindows({"--scratchpad"}, function(windows, queryError)
      if queryError then
        done(nil, queryError)
        return
      end
      if #windows == 1 and windows[1].id == id then
        done(windows[1], nil)
      elseif #windows > 0 then
        done(nil, "A different window owns the OmniWM scratchpad")
      else
        done(false, nil)
      end
    end)
  end, 5, function(window, pollError)
    if pollError then
      M.notify(pollError)
    elseif window.isVisible then
      focusVisibleScratchpad(id)
    else
      M.run({"command", "scratchpad", "toggle"}, function(_, toggleError)
        if toggleError then
          M.notify(toggleError)
          return
        end
        focusVisibleScratchpad(id)
      end)
    end
  end)
end

local function assignFinderScratchpad(window)
  downloads.assignNewScratchpad(window, {
    notify = M.notify,
    queryScratchpad = function(callback)
      queryWindows({"--scratchpad"}, callback)
    end,
    queryTarget = function(id, callback)
      queryWindows({"--window", id}, function(windows, queryError)
        callback(windows and findWindowByID(windows, id), queryError)
      end)
    end,
    assign = function(callback)
      M.run({"command", "scratchpad", "assign"}, callback)
    end,
    show = showScratchpadIfHidden,
    done = downloads.finishCreation,
  })
end

local function createDownloadsFinder(previousIDs)
  if not downloads.beginCreation(M.notify) then
    return
  end

  local script = [[
    set downloadsFolder to POSIX file ((system attribute "HOME") & "/Downloads")
    tell application "Finder"
      activate
      set downloadsWindow to make new Finder window
      set target of downloadsWindow to downloadsFolder
    end tell
  ]]
  local success, result = hs.osascript.applescript(script)
  if not success then
    downloads.finishCreation()
    M.notify("Could not create the Downloads Finder window: " .. tostring(result))
    return
  end
  pollNewWindow("com.apple.finder", previousIDs, function(window, pollError)
    if pollError then
      downloads.finishCreation()
      M.notify(pollError)
      return
    end
    pollWindow(window.id, downloads.isFocused, function(focusedWindow, focusError)
      if focusError then
        downloads.finishCreation()
        M.notify(focusError)
        return
      end
      assignFinderScratchpad(focusedWindow)
    end)
  end)
end

function M.toggleDownloadsScratchpad()
  queryWindows({"--scratchpad"}, function(scratchpad, scratchpadError)
    if scratchpadError then
      M.notify(scratchpadError)
      return
    end
    if #scratchpad > 1 then
      M.notify("OmniWM returned more than one scratchpad window")
      return
    end
    if #scratchpad == 1 then
      if bundleID(scratchpad[1]) ~= "com.apple.finder" then
        M.notify("Another window owns the OmniWM scratchpad")
        return
      end
      if scratchpad[1].isVisible then
        M.run({"command", "scratchpad", "toggle"}, M.reportResult)
      else
        showScratchpadIfHidden(scratchpad[1].id)
      end
      return
    end

    M.windows(function(windows, windowsError)
      if windowsError then
        M.notify(windowsError)
        return
      end
      local previousIDs = {}
      for _, window in ipairs(windows) do
        if bundleID(window) == "com.apple.finder" then
          previousIDs[window.id] = true
        end
      end
      createDownloadsFinder(previousIDs)
    end)
  end)
end

local function moveWindowToWorkspaceWithCallback(window, destination, callback)
  M.run({"window", "navigate", window.id}, function(_, navigateError)
    if navigateError then
      callback(nil, navigateError)
      return
    end
    pollWindow(window.id, function(candidate)
      return candidate.isFocused == true
    end, function(_, focusError)
      if focusError then
        callback(nil, focusError)
        return
      end
      M.run({"command", "move-to-workspace", tostring(destination)}, function(_, moveError)
        if moveError then
          callback(nil, moveError)
          return
        end
        pollWindow(window.id, function(candidate)
          return workspaceNumber(candidate) == destination
        end, callback)
      end)
    end)
  end)
end

local function moveWindowToWorkspace(window, destination)
  moveWindowToWorkspaceWithCallback(window, destination, function(_, moveError)
    if moveError then
      M.notify(moveError)
    end
  end)
end

local function summonWindow(window, callback, activeWorkspace)
  if window.isVisible == true
    or (activeWorkspace and workspaceNumber(window) == activeWorkspace.number) then
    callback(window, nil)
    return
  end

  M.run({"window", "summon-right", window.id}, function(_, summonError)
    if summonError then
      callback(nil, summonError)
      return
    end
    pollWindow(window.id, function(candidate)
      return candidate.isVisible == true
    end, callback)
  end)
end

local function summonPhotos(window)
  M.run({"window", "summon-right", window.id}, function(_, summonError)
    if summonError then
      M.notify(summonError)
      return
    end
    pollWindow(window.id, function(candidate)
      return candidate.isVisible == true
    end, function(_, visibilityError)
      if visibilityError then
        M.notify(visibilityError)
        return
      end
      focusSummonedWindow(window.id, function(_, focusError)
        if focusError then
          M.notify(focusError)
        end
      end)
    end)
  end)
end

local function placePhotos(window, activeWorkspace)
  if window.isVisible == true or workspaceNumber(window) == activeWorkspace.number then
    moveWindowToWorkspace(window, 10)
  else
    summonPhotos(window)
  end
end

local function showNewPhotos(window, activeWorkspace)
  if window.isVisible == true or workspaceNumber(window) == activeWorkspace.number then
    focusSummonedWindow(window.id, function(_, focusError)
      if focusError then
        M.notify(focusError)
      end
    end)
  else
    summonPhotos(window)
  end
end

local function launchPhotos(previousIDs, activeWorkspace)
  if not hs.application.launchOrFocusByBundleID("com.apple.Photos") then
    M.notify("Could not launch Photos")
    return
  end
  pollNewWindow("com.apple.Photos", previousIDs, function(window, pollError)
    if pollError then
      M.notify(pollError)
      return
    end
    showNewPhotos(window, activeWorkspace)
  end)
end

function M.togglePhotos()
  M.activeWorkspace(function(activeWorkspace, workspaceError)
    if workspaceError then
      M.notify(workspaceError)
      return
    end
    M.windows(function(windows, windowsError)
      if windowsError then
        M.notify(windowsError)
        return
      end
      local photos = findWindows(windows, function(window)
        return bundleID(window) == "com.apple.Photos"
      end)
      if #photos > 1 then
        M.notify("More than one Photos window is managed by OmniWM")
      elseif #photos == 1 then
        placePhotos(photos[1], activeWorkspace)
      else
        local previousIDs = {}
        for _, window in ipairs(windows) do
          previousIDs[window.id] = true
        end
        launchPhotos(previousIDs, activeWorkspace)
      end
    end)
  end)
end

local function openNormallyInSafari(url)
  if not hs.urlevent.openURLWithBundle(url, "com.apple.Safari") then
    M.notify("Could not open the URL in Safari")
  end
end

local function isWorkSafari(window)
  local title = window.title or ""
  return title:find("Work —", 1, true) ~= nil
end

local function resolveDedicatedSafari(windows)
  local hint = hs.settings.get(dedicatedSafariWindowKey)
  if type(hint) == "string" then
    local hinted = findWindowByID(windows, hint)
    if hinted and urlSource.isSafariBrowserWindow(hinted) and not isWorkSafari(hinted) then
      return hinted, nil
    end
    hs.settings.clear(dedicatedSafariWindowKey)
  end

  local candidates = findWindows(windows, function(window)
    return urlSource.isSafariBrowserWindow(window)
      and workspaceNumber(window) == 3
      and not isWorkSafari(window)
  end)
  if #candidates == 1 then
    hs.settings.set(dedicatedSafariWindowKey, candidates[1].id)
    return candidates[1], nil
  elseif #candidates == 0 then
    return nil, nil
  end
  return nil, "More than one Safari window can be the dedicated Ghostty window"
end

local function createDedicatedSafari(windows, callback)
  local previousIDs = {}
  for _, window in ipairs(windows) do
    if bundleID(window) == "com.apple.Safari" then
      previousIDs[window.id] = true
    end
  end

  local success, result = hs.osascript.applescript([[
    tell application "Safari"
      activate
      make new document
    end tell
  ]])
  if not success then
    callback(nil, "Could not create the dedicated Safari window: " .. tostring(result))
    return
  end

  pollNewWindow("com.apple.Safari", previousIDs, function(window, pollError)
    if pollError then
      callback(nil, pollError)
      return
    end
    if isWorkSafari(window) then
      callback(nil, "The new Safari window matched the Work window marker")
      return
    end
    moveWindowToWorkspaceWithCallback(window, 3, function(movedWindow, moveError)
      if moveError then
        callback(nil, moveError)
        return
      end
      hs.settings.set(dedicatedSafariWindowKey, movedWindow.id)
      callback(movedWindow, nil)
    end)
  end, urlSource.isSafariBrowserWindow)
end

local function safariNativeWindowID(window)
  if type(window.id) ~= "string" or window.id:sub(1, 3) ~= "ow_" then
    return nil
  end
  local decodeOK, decoded = pcall(hs.base64.decode, window.id:sub(4))
  if not decodeOK or type(decoded) ~= "string" then
    return nil
  end
  return tonumber(decoded:match(":(%d+)$"))
end

local function openSafariTab(window, url)
  local nativeWindowID = safariNativeWindowID(window)
  if not nativeWindowID then
    return nil, "Could not resolve the dedicated Safari window ID"
  end
  local script = string.format([[
    tell application "Safari"
      set targetWindow to first window whose id is %d
      tell targetWindow
        set newTab to make new tab at end of tabs with properties {URL:%s}
        set current tab to newTab
      end tell
      activate
    end tell
  ]], nativeWindowID, appleScriptLiteral(url))
  local success, result = hs.osascript.applescript(script)
  if not success then
    return nil, "Could not open the Safari tab: " .. tostring(result)
  end
  return true, nil
end

local function openURLInExactSafariWindow(safariWindow, url, focusAfterOpen)
  local _, tabError = openSafariTab(safariWindow, url)
  if tabError then
    M.notify(tabError)
    openNormallyInSafari(url)
    return
  end
  if focusAfterOpen then
    M.run({"window", "focus", safariWindow.id}, M.reportResult)
  end
end

local function openURLInDedicatedSafari(safariWindow, activeWorkspace, url)
  if workspaceNumber(safariWindow) == activeWorkspace.number then
    openURLInExactSafariWindow(safariWindow, url, true)
    return
  end

  summonWindow(safariWindow, function(_, summonError)
    if summonError then
      M.notify(summonError)
      openNormallyInSafari(url)
      return
    end
    focusSummonedWindow(safariWindow.id, function(_, focusError)
      if focusError then
        M.notify(focusError)
        openNormallyInSafari(url)
        return
      end
      openURLInExactSafariWindow(safariWindow, url, false)
    end)
  end, activeWorkspace)
end

local function routeGhosttyURL(url)
  M.activeWorkspace(function(activeWorkspace, workspaceError)
    if workspaceError then
      M.notify(workspaceError)
      openNormallyInSafari(url)
      return
    end
    M.windows(function(windows, windowsError)
      if windowsError then
        M.notify(windowsError)
        openNormallyInSafari(url)
        return
      end
      local safariWindow, resolveError = resolveDedicatedSafari(windows)
      if resolveError then
        M.notify(resolveError)
        openNormallyInSafari(url)
      elseif safariWindow then
        openURLInDedicatedSafari(safariWindow, activeWorkspace, url)
      else
        createDedicatedSafari(windows, function(createdWindow, createError)
          if createError then
            M.notify(createError)
            openNormallyInSafari(url)
            return
          end
          openURLInDedicatedSafari(createdWindow, activeWorkspace, url)
        end)
      end
    end)
  end)
end

hs.hotkey.bind({"ctrl", "alt"}, "D", M.toggleDownloadsScratchpad)
hs.hotkey.bind({"ctrl", "alt"}, "P", M.togglePhotos)
local cheatsheetHotkey = hs.hotkey.bind({"ctrl", "alt"}, "H", function()
  cheatsheetPanel:toggle()
end)
hs.hotkey.bind({"alt"}, "0", function()
  M.run({"command", "switch-workspace", "10"}, M.reportResult)
end)
hs.hotkey.bind({"alt", "shift"}, "0", function()
  M.run({"command", "move-to-workspace", "10"}, M.reportResult)
end)

local function routeURL(fullURL, senderPID, senderBundle, routeGhostty)
  local decision = routeGhostty and "ghostty" or "normal"
  logger.i(string.format(
    "URL source pid=%s bundle=%s decision=%s",
    tostring(senderPID),
    tostring(senderBundle),
    decision
  ))
  if routeGhostty then
    routeGhosttyURL(fullURL)
  else
    openNormallyInSafari(fullURL)
  end
end

hs.urlevent.httpCallback = function(_, _, _, fullURL, senderPID)
  local sender
  if type(senderPID) == "number" and senderPID > 0 then
    sender = hs.application.applicationForPID(senderPID)
  end
  local senderBundle = sender and sender:bundleID() or nil
  if senderBundle and senderBundle ~= "org.hammerspoon.Hammerspoon" then
    routeURL(
      fullURL,
      senderPID,
      senderBundle,
      urlSource.shouldRouteGhostty(senderBundle, nil, nil)
    )
    return
  end

  M.activeWorkspace(function(activeWorkspace, workspaceError)
    if workspaceError then
      M.notify(workspaceError)
      routeURL(fullURL, senderPID, senderBundle, false)
      return
    end
    M.windows(function(windows, windowsError)
      if windowsError then
        M.notify(windowsError)
        routeURL(fullURL, senderPID, senderBundle, false)
        return
      end
      routeURL(
        fullURL,
        senderPID,
        senderBundle,
        urlSource.shouldRouteGhostty(senderBundle, activeWorkspace.number, windows)
      )
    end)
  end)
end

return M
