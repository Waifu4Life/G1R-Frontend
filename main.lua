-- G1R Frontend: a launcher for Gen1 Recomp.
--
-- Controls
--   Keyboard: arrows move, Enter picks, Esc goes back, Page Up / Page Down
--             step through the five tabs.
--   Gamepad:  D-pad or left stick moves, A picks, B goes back, LB / RB step
--             through the tabs.
--   Mouse:    point and click, wheel scrolls, right-click goes back.
--   Drop a picture on a game to use it as its art, or a mod .zip on the
--   window to install it.

local UI = require("fe.ui")
local FS = require("fe.nativefs")
local R = require("fe.recomp")
local O = require("fe.overlays")
local Config = require("fe.config")
local Main = require("fe.mainscreen")

local App = {}
local stack = {}
local canvas
local view = { scale = 1, ox = 0, oy = 0 }
local items = {}
local toast = { text = nil, time = 0 }
local busyText
local lastMouse = { x = -1, y = -1 }
local windowSaveTimer = 0

---------------------------------------------------------------------------
-- Screen stack (main screen at the bottom, pop-ups above it)
---------------------------------------------------------------------------
local function top() return stack[#stack] end

function App.push(screen)
  stack[#stack + 1] = screen
  screen.focus = nil
end

function App.pop()
  if #stack > 1 then table.remove(stack) end
end

function App.setFocus(id) top().focus = id end

function App.toScreen(x, y, w, h) return x, y, w, h end   -- scissor works in canvas pixels

function App.toast(text)
  toast.text, toast.time = text, 3
end

function App.busy(text) busyText = text end

-- Network jobs run on the helper thread; cb(result) runs when it answers.
local pending, nextId = {}, 0
function App.request(job, cb)
  nextId = nextId + 1
  job.id = nextId
  pending[nextId] = cb
  App.updateIn:push(job)
end

-- A long task with a :step() method (ID Sync). Runs a little each frame
-- behind a busy screen; done(ok, job, err) when it finishes.
local runningJob
function App.runJob(title, job, done)
  runningJob = { title = title, job = job, done = done }
  busyText = title
end

---------------------------------------------------------------------------
-- Window: fullscreen or a normal window, remembered between sessions
---------------------------------------------------------------------------
local function rememberWindow()
  if love.window.getFullscreen() then return end
  local w, h = love.window.getMode()
  local x, y, display = love.window.getPosition()
  local maximized = love.window.isMaximized and love.window.isMaximized() or false
  local cur = Config.data.window or {}
  if maximized then
    -- keep the size it had before it was maximized
    cur.maximized = true
  else
    cur = { w = w, h = h, x = x, y = y, display = display, maximized = false }
  end
  Config.data.window = cur
end

-- Back to a normal window: the remembered size and place, or (first time)
-- three quarters of the screen, centred. LOVE keeps a fullscreen window's
-- size when fullscreen is switched off, so the size is always set here.
local function restoreWindow()
  local win = Config.data.window
  local display = type(win) == "table" and tonumber(win.display) or 1
  local dw, dh = love.window.getDesktopDimensions(display)
  local w, h, x, y
  if type(win) == "table" and tonumber(win.w) and tonumber(win.h)
      and win.w < dw and win.h < dh then
    w, h, x, y = win.w, win.h, win.x, win.y
  else
    w, h = math.floor(dw * 0.75), math.floor(dh * 0.75)
    x, y = math.floor((dw - w) / 2), math.floor((dh - h) / 2)
  end
  local flags = { fullscreen = false, borderless = false, resizable = true,
    minwidth = 640, minheight = 360, highdpi = true, display = display, x = x, y = y }
  local ok = pcall(love.window.setMode, w, h, flags)
  if not ok then pcall(love.window.updateMode, w, h, flags) end
  if type(win) == "table" and win.maximized and love.window.maximize then pcall(love.window.maximize) end
end

function App.setFullscreen(full)
  if full == love.window.getFullscreen() then return end
  if full then
    rememberWindow()
    love.window.setFullscreen(true, "desktop")
  else
    restoreWindow()
  end
  Config.data.fullscreen = full
  Config.save()
end

function App.toggleFullscreen() App.setFullscreen(not love.window.getFullscreen()) end

function App.message(title, text, buttons)
  App.push(O.message(title, text, buttons))
end

local function useFolder(dir)
  R.setup(dir)
  if not R.exe then
    App.message("Gen1 Recomp not found",
      "That folder doesn't have the Gen1 Recomp program in it. Pick the folder that holds gen1recomp"
      .. (FS.windows and ".exe." or "."), {
      { label = "Try again", onPress = function() App.askFolder() end },
      { label = "Back" },
    })
    R.root = nil
    return
  end
  Config.set("recompDir", dir)
  pcall(R.installCompanion)
  Main.refreshAll()
  App.toast("Gen1 Recomp found" .. (R.portable and " (portable)" or ""))
end

function App.askFolder()
  App.message("Where is Gen1 Recomp?",
    "Pick the folder that holds the Gen1 Recomp program. The frontend remembers it.", {
    { label = "Find folder", fill = UI.colors.green, onPress = function()
      App.push(O.fileBrowser({ title = "Gen1 Recomp folder", folders = true,
        start = Config.data.recompDir,
        hint = "Open the folder with Gen1 Recomp in it, then press \"Use this folder\".",
        onPick = useFolder }))
    end },
    { label = "Later" },
  })
end

O.app = App

---------------------------------------------------------------------------
-- Finding Gen1 Recomp on start-up
---------------------------------------------------------------------------
local function autoDetect()
  local candidates = {}
  if Config.data.recompDir then candidates[#candidates + 1] = Config.data.recompDir end
  local base = love.filesystem.getSourceBaseDirectory and love.filesystem.getSourceBaseDirectory()
  if base then
    base = FS.norm(base)
    candidates[#candidates + 1] = base
    local par = FS.parent(base)
    if par then candidates[#candidates + 1] = par end
  end
  local src = love.filesystem.getSource and love.filesystem.getSource()
  if src then candidates[#candidates + 1] = FS.norm(src) end
  for _, dir in ipairs(candidates) do
    if R.findExe(dir) then
      R.setup(dir)
      if Config.data.recompDir ~= dir then Config.set("recompDir", dir) end
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- LOVE callbacks
---------------------------------------------------------------------------
function love.load()
  love.graphics.setDefaultFilter("linear", "linear")
  love.keyboard.setKeyRepeat(true)
  canvas = love.graphics.newCanvas(UI.W, UI.H)
  Config.load()
  -- open the way it was left: fullscreen, or a window at its old size and place
  if Config.data.fullscreen == false then
    restoreWindow()
  else
    pcall(love.window.setFullscreen, true, "desktop")
  end
  local found = autoDetect()
  if found then pcall(R.installCompanion) end
  Main.init(App)
  stack = { Main }
  App.updateIn = love.thread.getChannel("fe_update_in")
  App.updateOut = love.thread.getChannel("fe_update_out")
  local thread = love.thread.newThread("fe/update_worker.lua")
  thread:start()
  App.thread = thread
  if not found then App.askFolder() end
end

local function computeView()
  local w, h = love.graphics.getDimensions()
  local s = math.min(w / UI.W, h / UI.H)
  view.scale = s
  view.ox = math.floor((w - UI.W * s) / 2)
  view.oy = math.floor((h - UI.H * s) / 2)
end

local function toDesign(x, y)
  return (x - view.ox) / view.scale, (y - view.oy) / view.scale
end

local function rebuild()
  local screen = top()
  items = screen:build() or {}
  if not screen.focus or not UI.findItem(items, screen.focus) then
    local id = screen.defaultFocus and screen:defaultFocus()
    if not (id and UI.findItem(items, id)) then
      local first = UI.firstFocusable(items)
      id = first and first.id or nil
    end
    screen.focus = id
  end
end

local function focusItem() return UI.findItem(items, top().focus) end

local function press(item)
  if not item then return end
  -- picking anything outside an open Menu closes it
  if #stack == 1 and Main.menuOpen and item.kind ~= "dd" and item.kind ~= "menu" then
    Main.menuOpen = nil
  end
  if item.disabled then
    if item.onPress then item.onPress() end   -- lets disabled buttons explain themselves
    return
  end
  if item.onPress then item.onPress() end
end

local function navigate(dx, dy, source)
  if busyText then return end
  local screen = top()
  if screen.nav and screen:nav(dx, dy) then return end
  rebuild()
  local id = UI.moveFocus(items, screen.focus, dx, dy)
  if id ~= screen.focus then
    screen.focus = id
    local it = UI.findItem(items, id)
    if it and screen.onFocus then screen:onFocus(it, source or "keys") end
  end
end

local function accept()
  if busyText then return end
  rebuild()
  press(focusItem())
end

local function back()
  if busyText then return end
  local screen = top()
  if screen.back then screen:back() end
end

local function stepTab(dir)
  if busyText then return end
  if #stack == 1 and Main.stepTab then Main:stepTab(dir) end
end

function love.update(dt)
  if toast.time > 0 then toast.time = toast.time - dt end
  if windowSaveTimer > 0 then
    windowSaveTimer = windowSaveTimer - dt
    if windowSaveTimer <= 0 then rememberWindow() Config.save() end
  end
  -- results from the update thread
  local res = App.updateOut and App.updateOut:pop()
  while res do
    local cb = pending[res.id]
    pending[res.id] = nil
    if cb then
      local ok, err = pcall(cb, res)
      if not ok then App.message("Error", tostring(err)) end
    end
    res = App.updateOut:pop()
  end
  if runningJob then
    local rj = runningJob
    local t0 = love.timer.getTime()
    local ok, finished
    repeat
      ok, finished = pcall(rj.job.step, rj.job)
    until not ok or finished or love.timer.getTime() - t0 > 0.03
    local pct = 0
    if ok and rj.job.progress then
      local okP, p = pcall(rj.job.progress, rj.job)
      pct = okP and tonumber(p) or 0
    end
    busyText = ("%s  %d%%"):format(rj.title, math.floor(pct * 100))
    if not ok or finished then
      runningJob = nil
      busyText = nil
      rj.done(ok, rj.job, not ok and finished or nil)
    end
  end
  if App.thread then
    local err = App.thread:getError()
    if err then
      App.thread = nil
      if not runningJob then busyText = nil end
      App.message("Updates", "The update helper stopped: " .. tostring(err))
    end
  end
  -- held D-pad / stick repeat
  App.pollStick(dt)
end

function love.draw()
  computeView()
  rebuild()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  for i, screen in ipairs(stack) do
    if i == #stack then
      screen:draw(items, screen.focus)
    else
      screen:draw(screen:build() or {}, nil)
    end
  end
  if toast.time > 0 and toast.text then
    local font = UI.sans(26)
    local w = font:getWidth(toast.text) + 60
    local x = (UI.W - w) / 2
    love.graphics.setColor(0.1, 0.1, 0.1, 0.92)
    love.graphics.rectangle("fill", x, UI.H - 170, w, 56, 12, 12)
    UI.textCentered(toast.text, font, x, UI.H - 170, w, 56, UI.colors.white)
  end
  if busyText then
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, UI.W, UI.H)
    UI.textCentered(busyText, UI.pixel(44), 0, 0, UI.W, UI.H, UI.colors.white)
  end
  love.graphics.setCanvas()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, view.ox, view.oy, 0, view.scale, view.scale)
end

function love.resize()
  computeView()
  windowSaveTimer = 1.5   -- remember the new size once resizing settles
end

function love.quit()
  rememberWindow()
  Config.data.fullscreen = love.window.getFullscreen()
  Config.save()
  return false
end

-- Coming back to the frontend (after playing) re-reads saves and mods.
function love.focus(f)
  if f and #stack >= 1 then Main.refreshAll() end
end

function love.keypressed(key)
  local screen = top()
  if screen.keypressed and screen:keypressed(key) then return end
  if key == "up" then navigate(0, -1)
  elseif key == "down" then navigate(0, 1)
  elseif key == "left" then navigate(-1, 0)
  elseif key == "right" then navigate(1, 0)
  elseif key == "return" or key == "kpenter" then accept()
  elseif key == "escape" then back()
  elseif key == "pageup" then stepTab(-1)
  elseif key == "pagedown" then stepTab(1)
  elseif key == "f5" then Main.refreshAll() App.toast("Refreshed")
  elseif key == "f11" then App.toggleFullscreen()
  end
end

function love.textinput(t)
  local screen = top()
  if screen.textinput then screen:textinput(t) end
end

---------------------------------------------------------------------------
-- Gamepad (XInput layout: A picks, B goes back)
---------------------------------------------------------------------------
local held = { dir = nil, timer = 0 }
local DIRS = { dpup = { 0, -1 }, dpdown = { 0, 1 }, dpleft = { -1, 0 }, dpright = { 1, 0 } }

function love.gamepadpressed(_, button)
  -- the Confirm / Cancel swap only changes the controller
  if Config.data.swapAB then
    if button == "a" then button = "b" elseif button == "b" then button = "a" end
  end
  local d = DIRS[button]
  if d then
    navigate(d[1], d[2])
    held.dir, held.timer, held.src = d, 0.38, button
    return
  end
  if button == "a" then accept()
  elseif button == "b" then back()
  elseif button == "leftshoulder" then stepTab(-1)
  elseif button == "rightshoulder" then stepTab(1)
  end
end

function love.gamepadreleased(_, button)
  if held.src == button then held.dir = nil end
end

function App.pollStick(dt)
  -- left stick behaves like the D-pad
  local dir
  for _, js in ipairs(love.joystick.getJoysticks()) do
    if js:isGamepad() then
      local x, y = js:getGamepadAxis("leftx"), js:getGamepadAxis("lefty")
      if math.abs(x) > 0.6 or math.abs(y) > 0.6 then
        if math.abs(x) > math.abs(y) then dir = { x > 0 and 1 or -1, 0 }
        else dir = { 0, y > 0 and 1 or -1 } end
      end
    end
  end
  if dir then
    if held.src ~= "stick" or held.dir[1] ~= dir[1] or held.dir[2] ~= dir[2] then
      navigate(dir[1], dir[2])
      held.dir, held.timer, held.src = dir, 0.38, "stick"
      return
    end
  elseif held.src == "stick" then
    held.dir = nil
  end
  if held.dir then
    held.timer = held.timer - dt
    if held.timer <= 0 then
      navigate(held.dir[1], held.dir[2])
      held.timer = 0.09
    end
  end
end

---------------------------------------------------------------------------
-- Mouse
---------------------------------------------------------------------------
function love.mousemoved(x, y)
  if busyText then return end
  if math.abs(x - lastMouse.x) < 2 and math.abs(y - lastMouse.y) < 2 then return end
  lastMouse.x, lastMouse.y = x, y
  local mx, my = toDesign(x, y)
  rebuild()
  local it = UI.hit(items, mx, my)
  local screen = top()
  if it and it.id ~= screen.focus then
    screen.focus = it.id
    if screen.onFocus then screen:onFocus(it, "mouse") end
  end
end

function love.mousepressed(x, y, button)
  if busyText then return end
  local mx, my = toDesign(x, y)
  if button == 1 then
    rebuild()
    local it = UI.hit(items, mx, my)
    if it then
      top().focus = it.id
      press(it)
    end
  elseif button == 2 then
    back()
  end
end

function love.wheelmoved(_, dy)
  local screen = top()
  if screen.wheel then screen:wheel(dy) end
end

---------------------------------------------------------------------------
-- Drag and drop
---------------------------------------------------------------------------
function love.filedropped(file)
  local path = FS.norm(file:getFilename())
  local ext = FS.ext(path)
  if #stack > 1 then return end
  rebuild()
  local mx, my = toDesign(love.mouse.getPosition())
  local over = UI.hit(items, mx, my) or focusItem()
  if ext == "zip" then
    Main.importModZip(path)
  elseif ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "bmp" or ext == "tga" then
    if over and over.game then Main.setCustomArt(over.game, path)
    else App.toast("Drop the picture on a game to use it as its art.") end
  elseif ext == "sav" or ext == "srm" then
    if over and over.game and not over.game.spinoff then Main.importSave(over.game, path)
    else App.toast("Drop the save on a game to import it.") end
  end
end
