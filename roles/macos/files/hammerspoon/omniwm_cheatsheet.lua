local M = {}

local function htmlEscape(value)
  return value
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
    :gsub("'", "&#39;")
end

local function panelHTML(markdown)
  return [[<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none'; style-src 'unsafe-inline'">
<style>
  :root { color-scheme: light dark; }
  body {
    box-sizing: border-box;
    margin: 0;
    padding: 24px;
    background: Canvas;
    color: CanvasText;
  }
  pre {
    margin: 0;
    font: 14px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
</style>
</head>
<body><pre>]] .. htmlEscape(markdown) .. [[</pre></body>
</html>]]
end

local function boundedSize(available, proportion, minimum, maximum)
  local upper = math.min(available, maximum)
  local lower = math.min(available, minimum)
  return math.max(lower, math.min(upper, math.floor(available * proportion)))
end

local function centeredFrame(screenFrame)
  local width = boundedSize(screenFrame.w, 0.68, 520, 1000)
  local height = boundedSize(screenFrame.h, 0.78, 480, 850)
  return {
    x = math.floor(screenFrame.x + (screenFrame.w - width) / 2),
    y = math.floor(screenFrame.y + (screenFrame.h - height) / 2),
    w = width,
    h = height,
  }
end

local function readFile(path)
  local file, openError = io.open(path, "r")
  if not file then
    return nil, openError
  end

  local ok, content, readError = pcall(file.read, file, "*a")
  file:close()
  if not ok then
    return nil, content
  end
  if content == nil then
    return nil, readError
  end
  return content, nil
end

function M.new(options)
  options = options or {}
  local runtime = options.hs or hs
  local path = options.path or
    (os.getenv("HOME") .. "/.local/share/omniwm/omniwm-cheatsheet.md")
  local notify = options.notify or function(message)
    runtime.notify.new({
      title = "OmniWM Cheat Sheet",
      informativeText = tostring(message),
    }):send()
  end

  local controller = {}
  local panel
  local escapeHotkey

  function controller:hide()
    if escapeHotkey then
      escapeHotkey:disable()
    end
    if panel and panel:isVisible() then
      panel:hide()
    end
  end

  escapeHotkey = runtime.hotkey.new({}, "escape", function()
    controller:hide()
  end)
  escapeHotkey:disable()

  local function ensurePanel(frame)
    if panel then
      panel:frame(frame)
      return panel
    end

    panel = runtime.webview.new(frame, {
      javaScriptEnabled = false,
      javaScriptCanOpenWindowsAutomatically = false,
      developerExtrasEnabled = false,
      privateBrowsing = true,
    })
      :windowStyle({"titled", "resizable", "utility"})
      :windowTitle("OmniWM Cheat Sheet")
      :level(runtime.drawing.windowLevels.floating)
      :behaviorAsLabels({"canJoinAllSpaces", "fullScreenAuxiliary"})
      :allowNewWindows(false)
    return panel
  end

  function controller:show()
    self:hide()

    local markdown, readError = readFile(path)
    if not markdown then
      notify("Could not read OmniWM cheat sheet: " .. tostring(readError))
      return false
    end

    local screen = runtime.mouse.getCurrentScreen()
    if not screen then
      notify("Could not find the current display for the OmniWM cheat sheet")
      return false
    end

    local currentPanel = ensurePanel(centeredFrame(screen:frame()))
    currentPanel:html(panelHTML(markdown))
    currentPanel:show()
    escapeHotkey:enable()
    return true
  end

  function controller:toggle()
    if panel and panel:isVisible() then
      self:hide()
      return false
    end
    return self:show()
  end

  return controller
end

M.htmlEscape = htmlEscape
M.panelHTML = panelHTML
M.centeredFrame = centeredFrame

return M
