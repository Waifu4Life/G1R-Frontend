-- Pop-up screens that sit on top of the main screen.
-- Each one gives main.lua a list of focusable items every frame (so mouse,
-- keyboard and gamepad all work the same way) and draws itself.
--
--   O.list(title, rows, opts)        pick one row (Saves, carts, art...)
--   O.message(title, text, buttons)  a note or a yes/no question
--   O.textInput(title, text, onDone) typing, with an on-screen keyboard
--   O.fileBrowser(opts)              pick a file or folder on the computer
--   O.textViewer(title, text)        long scrolling text (patch notes)

local UI = require("fe.ui")
local FS = require("fe.nativefs")

local O = {}

local PW = 1100           -- panel width
local ROW_H = 86

local function panelRect(h)
  local x = math.floor((UI.W - PW) / 2)
  local y = math.floor((UI.H - h) / 2)
  return x, y, PW, h
end

local function drawTitle(title, x, y, w)
  UI.textCentered(title, UI.pixel(44), x, y + 14, w, 60, UI.colors.white)
end

local function dimBehind()
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, UI.W, UI.H)
end

-- Scrolling list area shared by list, browser and viewer.
local function ensureVisible(self, item, top, height)
  if not item or not item.rowIndex then return end
  local rowTop = (item.rowIndex - 1) * self.rowH
  if rowTop < self.scroll then self.scroll = rowTop end
  if rowTop + self.rowH > self.scroll + height then
    self.scroll = rowTop + self.rowH - height
  end
end

local function clampScroll(self, count, height)
  local maxScroll = math.max(0, count * self.rowH - height)
  if self.scroll > maxScroll then self.scroll = maxScroll end
  if self.scroll < 0 then self.scroll = 0 end
end

---------------------------------------------------------------------------
-- List
-- rows: { label, detail, onPress(), disabled, marker = "ACTIVE" }
-- opts: { subtitle, buttons = { {label, onPress} }, keepOpen = bool }
---------------------------------------------------------------------------
function O.list(title, rows, opts)
  opts = opts or {}
  local self = { kind = "list", title = title, rows = rows, opts = opts,
                 scroll = 0, rowH = ROW_H }

  function self:geometry()
    local listH = math.min(#self.rows, 7) * ROW_H
    if #self.rows == 0 then listH = ROW_H end
    local h = 110 + (opts.subtitle and 40 or 0) + listH + 30 + 80
    local x, y, w = panelRect(h)
    local listY = y + 100 + (opts.subtitle and 40 or 0)
    return x, y, w, h, listY, listH
  end

  function self:build()
    local items = {}
    local x, y, w, h, listY, listH = self:geometry()
    clampScroll(self, #self.rows, listH)
    local clip = { x + 20, listY, w - 40, listH }
    for i, row in ipairs(self.rows) do
      items[#items + 1] = {
        id = "row" .. i, rowIndex = i, row = row,
        x = x + 20, y = listY + (i - 1) * ROW_H - self.scroll, w = w - 40, h = ROW_H - 8,
        clip = clip, disabled = row.disabled,
        onPress = function() if not row.disabled and row.onPress then row.onPress() end end,
      }
    end
    local buttons = opts.buttons or {}
    local bw = 260
    local total = #buttons * bw + (#buttons) * 20 + bw
    local bx = x + (w - total) / 2
    for i, b in ipairs(buttons) do
      items[#items + 1] = { id = "btn" .. i, label = b.label, x = bx, y = y + h - 90,
        w = bw, h = 64, fill = b.fill or UI.colors.tab, edge = UI.colors.tabBorder,
        disabled = b.disabled, onPress = b.onPress }
      bx = bx + bw + 20
    end
    items[#items + 1] = { id = "close", label = opts.closeLabel or "Back", x = bx, y = y + h - 90,
      w = bw, h = 64, fill = UI.colors.rename, edge = UI.colors.tabBorder,
      onPress = function() O.app.pop() end }
    return items
  end

  function self:onFocus(item)
    local _, _, _, _, _, listH = self:geometry()
    ensureVisible(self, item, 0, listH)
  end

  function self:wheel(dy)
    local _, _, _, _, _, listH = self:geometry()
    self.scroll = self.scroll - dy * ROW_H
    clampScroll(self, #self.rows, listH)
  end

  function self:draw(items, focusId)
    dimBehind()
    local x, y, w, h, listY, listH = self:geometry()
    UI.panel(x, y, w, h)
    drawTitle(self.title, x, y, w)
    if opts.subtitle then
      UI.textCentered(opts.subtitle, UI.sans(24), x, y + 76, w, 36, UI.colors.dim)
    end
    if #self.rows == 0 then
      UI.textCentered(opts.empty or "Nothing here yet.", UI.sans(28), x, listY, w, ROW_H, UI.colors.dim)
    end
    love.graphics.setScissor(O.app.toScreen(x + 20, listY, w - 40, listH))
    for _, it in ipairs(items) do
      if it.row and it.y + it.h > listY and it.y < listY + listH then
        local focused = it.id == focusId
        UI.setColor(focused and UI.colors.panel2 or UI.colors.panel, 1)
        love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 8, 8)
        love.graphics.setLineWidth(focused and 4 or 2)
        UI.setColor(focused and UI.colors.focus or UI.colors.panelEdge)
        love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 8, 8)
        local alpha = it.row.disabled and 0.4 or 1
        local textW = it.w - 40 - (it.row.marker and 220 or 0)
        UI.textClip(it.row.label, UI.sans(30), it.x + 20, it.y + 8, textW,
          { 1, 1, 1, alpha })
        if it.row.detail then
          UI.textClip(it.row.detail, UI.sans(22), it.x + 20, it.y + 44, textW,
            { UI.colors.dim[1], UI.colors.dim[2], UI.colors.dim[3], alpha })
        end
        if it.row.marker then
          UI.textCentered(it.row.marker, UI.sans(22), it.x + it.w - 230, it.y, 210, it.h,
            it.row.markerColor or UI.colors.ok)
        end
      end
    end
    love.graphics.setScissor()
    for _, it in ipairs(items) do
      if not it.row then UI.button(it, it.id == focusId) end
    end
  end

  function self:back() O.app.pop() return true end
  return self
end

---------------------------------------------------------------------------
-- Message: buttons = { { label, onPress } }; default is a single OK.
---------------------------------------------------------------------------
function O.message(title, text, buttons)
  buttons = buttons or { { label = "OK" } }
  local self = { kind = "message", title = title, text = text, buttons = buttons }

  function self:geometry()
    local font = UI.sans(28)
    local lines = UI.wrap(font, self.text, PW - 120)
    local h = 120 + #lines * font:getHeight() + 130
    local x, y, w = panelRect(h)
    return x, y, w, h, lines, font
  end

  function self:build()
    local x, y, w, h = self:geometry()
    local items = {}
    local bw = 280
    local total = #self.buttons * bw + (#self.buttons - 1) * 24
    local bx = x + (w - total) / 2
    for i, b in ipairs(self.buttons) do
      items[#items + 1] = { id = "btn" .. i, label = b.label, x = bx, y = y + h - 96,
        w = bw, h = 64, fill = b.fill or UI.colors.tab, edge = UI.colors.tabBorder,
        onPress = function()
          O.app.pop()
          if b.onPress then b.onPress() end
        end }
      bx = bx + bw + 24
    end
    return items
  end

  function self:draw(items, focusId)
    dimBehind()
    local x, y, w, h, lines, font = self:geometry()
    UI.panel(x, y, w, h)
    drawTitle(self.title, x, y, w)
    love.graphics.setFont(font)
    UI.setColor(UI.colors.white)
    for i, line in ipairs(lines) do
      love.graphics.print(line, x + 60, y + 100 + (i - 1) * font:getHeight())
    end
    for _, it in ipairs(items) do UI.button(it, it.id == focusId) end
  end

  function self:back()
    O.app.pop()
    local last = self.buttons[#self.buttons]
    if #self.buttons == 1 and last.onPress then last.onPress() end
    return true
  end
  return self
end

---------------------------------------------------------------------------
-- Text input with an on-screen keyboard for gamepads.
-- Keyboard: type, Backspace deletes, Enter saves, Esc cancels.
-- Gamepad: pick keys with the D-pad and A, B cancels.
---------------------------------------------------------------------------
local KEY_ROWS = {
  { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" },
  { "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T" },
  { "U", "V", "W", "X", "Y", "Z", "-", "'", ".", "!" },
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
}

function O.textInput(title, initial, onDone, maxLen)
  maxLen = maxLen or 24
  local self = { kind = "text", title = title, text = UI.safe(initial or ""), lower = false }

  local function add(ch)
    if #self.text < maxLen then self.text = self.text .. ch end
  end

  function self:submit()
    O.app.pop()
    love.keyboard.setTextInput(false)
    if onDone then onDone(self.text) end
  end

  function self:build()
    local h = 720
    local x, y, w = panelRect(h)
    local items = {}
    local kw, kh, gap = 92, 72, 10
    local gridW = 10 * kw + 9 * gap
    local gx = x + (w - gridW) / 2
    local gy = y + 230
    for r, row in ipairs(KEY_ROWS) do
      for c, ch in ipairs(row) do
        local label = self.lower and ch:lower() or ch
        items[#items + 1] = { id = "k" .. r .. "_" .. c, label = label,
          x = gx + (c - 1) * (kw + gap), y = gy + (r - 1) * (kh + gap), w = kw, h = kh,
          fill = UI.colors.tab, edge = UI.colors.tabBorder,
          onPress = function() add(label) end }
      end
    end
    local by = gy + 4 * (kh + gap) + 10
    local specials = {
      { "case", self.lower and "ABC" or "abc", 2, function() self.lower = not self.lower end },
      { "space", "Space", 3, function() add(" ") end },
      { "del", "Delete", 2, function() self.text = UI.dropLast(self.text) end },
      { "ok", "OK", 3, function() self:submit() end },
    }
    local sx = gx
    for _, s in ipairs(specials) do
      local sw = s[3] * kw + (s[3] - 1) * gap
      items[#items + 1] = { id = s[1], label = s[2], x = sx, y = by, w = sw, h = kh,
        fill = s[1] == "ok" and UI.colors.green or UI.colors.rename,
        edge = UI.colors.tabBorder, onPress = s[4] }
      sx = sx + sw + gap
    end
    return items
  end

  function self:draw(items, focusId)
    dimBehind()
    local x, y, w, h = panelRect(720)
    UI.panel(x, y, w, h)
    drawTitle(self.title, x, y, w)
    -- the text field
    UI.setColor(UI.colors.white)
    love.graphics.rectangle("fill", x + 80, y + 110, w - 160, 80, 8, 8)
    local font = UI.pixel(44)
    love.graphics.setFont(font)
    UI.setColor(UI.colors.text)
    local caret = (love.timer.getTime() % 1 < 0.5) and "_" or ""
    love.graphics.print(self.text .. caret, x + 100, y + 110 + (80 - font:getHeight()) / 2)
    for _, it in ipairs(items) do
      it.font = UI.pixel(33)
      UI.button(it, it.id == focusId)
    end
  end

  function self:textinput(t)
    for ch in t:gmatch("[%z\1-\127\194-\244][\128-\191]*") do add(ch) end
    return true
  end

  function self:keypressed(key)
    if key == "backspace" then self.text = UI.dropLast(self.text) return true end
    if key == "return" or key == "kpenter" then self:submit() return true end
    return false
  end

  function self:back()
    O.app.pop()
    love.keyboard.setTextInput(false)
    return true
  end

  love.keyboard.setTextInput(true)
  return self
end

---------------------------------------------------------------------------
-- File browser.
-- opts: { title, exts = { png = true }, start = dir, onPick(path),
--         folders = true -> picking a folder ("Use this folder") }
---------------------------------------------------------------------------
function O.fileBrowser(opts)
  local self = { kind = "browser", scroll = 0, rowH = 64, opts = opts }
  self.dir = opts.start and FS.isDir(opts.start) and FS.norm(opts.start) or FS.home()

  function self:load()
    self.entries = {}
    local par = FS.parent(self.dir)
    if par then self.entries[#self.entries + 1] = { name = "..", up = true, dir = true } end
    for _, e in ipairs(FS.list(self.dir)) do
      if e.dir or (not opts.folders and (not opts.exts or opts.exts[FS.ext(e.name) or ""])) then
        self.entries[#self.entries + 1] = e
      end
    end
    self.scroll = 0
  end
  self:load()

  function self:open(path)
    if FS.isDir(path) then
      self.dir = FS.norm(path)
      self:load()
      O.app.setFocus("row1")
    end
  end

  local LIST_TOP, LIST_H = 190, 9 * 64

  function self:build()
    local h = 920
    local x, y, w = panelRect(h)
    local items = {}
    local listY = y + LIST_TOP
    clampScroll(self, #self.entries, LIST_H)
    local clip = { x + 20, listY, w - 40, LIST_H }
    for i, e in ipairs(self.entries) do
      items[#items + 1] = { id = "row" .. i, rowIndex = i, entry = e,
        x = x + 20, y = listY + (i - 1) * self.rowH - self.scroll, w = w - 40, h = self.rowH - 6,
        clip = clip,
        onPress = function()
          if e.up then self:open(FS.parent(self.dir))
          elseif e.dir then self:open(FS.join(self.dir, e.name))
          else
            O.app.pop()
            opts.onPick(FS.join(self.dir, e.name))
          end
        end }
    end
    local buttons = {}
    buttons[#buttons + 1] = { "home", "Home", function() self:open(FS.home()) end }
    buttons[#buttons + 1] = { "roots", FS.windows and "Drives" or "Top", function()
      local roots = FS.roots()
      if #roots == 1 then self:open(roots[1]) return end
      local rows = {}
      for _, r in ipairs(roots) do
        rows[#rows + 1] = { label = r, onPress = function() O.app.pop() self:open(r) end }
      end
      O.app.push(O.list("Drives", rows))
    end }
    if opts.folders then
      buttons[#buttons + 1] = { "use", "Use this folder", function()
        O.app.pop()
        opts.onPick(self.dir)
      end }
    end
    buttons[#buttons + 1] = { "cancel", "Cancel", function() O.app.pop() end }
    local bw = 240
    local total = #buttons * bw + (#buttons - 1) * 20
    local bx = x + (w - total) / 2
    for _, b in ipairs(buttons) do
      items[#items + 1] = { id = b[1], label = b[2], x = bx, y = y + h - 96, w = bw, h = 64,
        fill = b[1] == "use" and UI.colors.green or UI.colors.tab,
        edge = UI.colors.tabBorder, onPress = b[3] }
      bx = bx + bw + 20
    end
    return items
  end

  function self:onFocus(item) ensureVisible(self, item, 0, LIST_H) end

  function self:wheel(dy)
    self.scroll = self.scroll - dy * self.rowH * 2
    clampScroll(self, #self.entries, LIST_H)
  end

  function self:keypressed(key)
    if key == "backspace" then
      local par = FS.parent(self.dir)
      if par then self:open(par) end
      return true
    end
    return false
  end

  function self:draw(items, focusId)
    dimBehind()
    local x, y, w, h = panelRect(920)
    UI.panel(x, y, w, h)
    drawTitle(opts.title or "Choose a file", x, y, w)
    UI.textClip(self.dir, UI.sans(24), x + 30, y + 90, w - 60, UI.colors.dim)
    UI.textClip(opts.hint or "Enter opens a folder. Backspace goes up a folder.",
      UI.sans(20), x + 30, y + 130, w - 60, UI.colors.dim)
    local listY = y + LIST_TOP
    love.graphics.setScissor(O.app.toScreen(x + 20, listY, w - 40, LIST_H))
    if #self.entries == 0 then
      UI.textCentered("This folder is empty.", UI.sans(26), x, listY, w, 64, UI.colors.dim)
    end
    for _, it in ipairs(items) do
      if it.entry and it.y + it.h > listY and it.y < listY + LIST_H then
        local focused = it.id == focusId
        UI.setColor(focused and UI.colors.panel2 or UI.colors.panel)
        love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 6, 6)
        if focused then
          love.graphics.setLineWidth(3)
          UI.setColor(UI.colors.focus)
          love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 6, 6)
        end
        local e = it.entry
        local label = e.up and "..  (up a folder)" or (e.dir and ("[" .. e.name .. "]") or e.name)
        UI.textClip(label, UI.sans(26), it.x + 18, it.y + 14, it.w - 36,
          e.dir and UI.colors.warn or UI.colors.white)
      end
    end
    love.graphics.setScissor()
    for _, it in ipairs(items) do
      if not it.entry then UI.button(it, it.id == focusId) end
    end
  end

  function self:back() O.app.pop() return true end
  return self
end

---------------------------------------------------------------------------
-- Long text you can scroll (patch notes, mod details).
---------------------------------------------------------------------------
function O.textViewer(title, text)
  local self = { kind = "viewer", title = title, scroll = 0, rowH = 1 }
  local font = UI.sans(24)
  local lines = UI.wrap(font, text, PW - 100)
  local LH = font:getHeight()
  local VIEW_H = 700

  function self:build()
    local x, y, w, h = panelRect(920)
    return { { id = "close", label = "Back", x = x + (w - 260) / 2, y = y + h - 90, w = 260, h = 64,
      fill = UI.colors.rename, edge = UI.colors.tabBorder, onPress = function() O.app.pop() end } }
  end

  local function clamp()
    local maxS = math.max(0, #lines * LH - VIEW_H)
    self.scroll = math.max(0, math.min(maxS, self.scroll))
  end

  function self:nav(dx, dy)
    if dy ~= 0 then self.scroll = self.scroll + dy * LH * 3 clamp() return true end
    return false
  end

  function self:wheel(dy) self.scroll = self.scroll - dy * LH * 3 clamp() end

  function self:draw(items, focusId)
    dimBehind()
    local x, y, w, h = panelRect(920)
    UI.panel(x, y, w, h)
    drawTitle(self.title, x, y, w)
    love.graphics.setScissor(O.app.toScreen(x + 40, y + 90, w - 80, VIEW_H))
    love.graphics.setFont(font)
    UI.setColor(UI.colors.white)
    local first = math.floor(self.scroll / LH) + 1
    for i = first, math.min(#lines, first + math.ceil(VIEW_H / LH) + 1) do
      love.graphics.print(lines[i], x + 50, y + 90 + (i - 1) * LH - self.scroll)
    end
    love.graphics.setScissor()
    for _, it in ipairs(items) do UI.button(it, it.id == focusId) end
  end

  function self:back() O.app.pop() return true end
  return self
end

---------------------------------------------------------------------------
-- Panel: a pop-up built from blocks, in the style of Gen1 Recomp's dialogs.
-- specFn() returns { title, subtitle, subColor, width, blocks = {...} }:
--   { kind = "text", text, color, size }
--   { kind = "buttons", cols = 2, height = 70, buttons = {
--       { id, label, onPress, style = "normal|blue|green|danger", disabled, keepOpen } } }
--   { kind = "save", title, badge, stats = { { "3", "badges" }, ... } }
--   { kind = "gap", h = 20 }
-- A button closes the panel before running onPress unless keepOpen is set.
---------------------------------------------------------------------------
local STYLE = {
  normal = { fill = { 0.11, 0.13, 0.16 }, edge = { 0.40, 0.43, 0.48 }, text = { 1, 1, 1 } },
  blue   = { fill = { 0.15, 0.42, 0.72 }, edge = { 0.15, 0.42, 0.72 }, text = { 1, 1, 1 } },
  green  = { fill = { 0.33, 0.90, 0.53 }, edge = { 0.33, 0.90, 0.53 }, text = { 0, 0, 0 } },
  danger = { fill = { 0.11, 0.13, 0.16 }, edge = { 0.75, 0.25, 0.28 }, text = { 1, 0.33, 0.36 } },
}
O.STYLE = STYLE

function O.darkButton(it, focused)
  local st = STYLE[it.style or "normal"] or STYLE.normal
  local a = it.disabled and 0.4 or 1
  UI.setColor(st.fill, a)
  love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 8, 8)
  love.graphics.setLineWidth(2)
  UI.setColor(st.edge, a)
  love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 8, 8)
  UI.textCentered(it.label, it.font or UI.sans(28), it.x, it.y, it.w, it.h,
    { st.text[1], st.text[2], st.text[3], a })
  if focused then UI.focusRing(it, 4) end
end

function O.panel(specFn)
  local self = { kind = "panel" }

  local function layout()
    local spec = specFn()
    local W = spec.width or 1100
    local pad = 44
    local inner = W - pad * 2
    local h = pad + 60 + (spec.subtitle and 44 or 0)
    local placed = {}
    for _, b in ipairs(spec.blocks or {}) do
      if b.kind == "text" then
        local font = UI.sans(b.size or 26)
        local lines = UI.wrap(font, b.text, inner)
        placed[#placed + 1] = { b = b, y = h, lines = lines, font = font }
        h = h + #lines * font:getHeight() + 14
      elseif b.kind == "buttons" then
        local cols = b.cols or 1
        local bh = b.height or 70
        local rows = math.ceil(#b.buttons / cols)
        placed[#placed + 1] = { b = b, y = h, cols = cols, bh = bh }
        h = h + rows * (bh + 16)
      elseif b.kind == "save" then
        placed[#placed + 1] = { b = b, y = h }
        h = h + 150
      elseif b.kind == "gap" then
        h = h + (b.h or 20)
      end
    end
    h = h + pad - 16
    local x = math.floor((UI.W - W) / 2)
    local y = math.max(10, math.floor((UI.H - h) / 2))
    return spec, x, y, W, h, pad, inner, placed
  end

  function self:build()
    local spec, x, y, W, h, pad, inner, placed = layout()
    local items = {}
    for _, p in ipairs(placed) do
      if p.b.kind == "buttons" then
        local gap = 16
        local bw = (inner - gap * (p.cols - 1)) / p.cols
        for i, btn in ipairs(p.b.buttons) do
          local col = (i - 1) % p.cols
          local row = math.floor((i - 1) / p.cols)
          items[#items + 1] = {
            id = btn.id or (p.b.id or "b") .. i, label = btn.label, style = btn.style,
            disabled = btn.disabled, font = btn.font,
            x = x + pad + col * (bw + gap), y = y + p.y + row * (p.bh + gap), w = bw, h = p.bh,
            onPress = function()
              if btn.disabled then
                if btn.whyDisabled then O.app.toast(btn.whyDisabled) end
                return
              end
              if not btn.keepOpen then O.app.pop() end
              if btn.onPress then btn.onPress() end
            end,
          }
        end
      end
    end
    self._geom = { spec = spec, x = x, y = y, W = W, h = h, pad = pad, inner = inner, placed = placed }
    return items
  end

  function self:draw(items, focusId)
    dimBehind()
    local g = self._geom
    if not g then return end
    local x, y, W, h, pad = g.x, g.y, g.W, g.h, g.pad
    UI.panel(x, y, W, h)
    UI.textClip(g.spec.title, UI.sans(40), x + pad, y + pad - 8, g.inner, UI.colors.white)
    if g.spec.subtitle then
      UI.textClip(g.spec.subtitle, UI.sans(26), x + pad, y + pad + 44, g.inner,
        g.spec.subColor or UI.colors.ok)
    end
    for _, p in ipairs(g.placed) do
      local b = p.b
      if b.kind == "text" then
        love.graphics.setFont(p.font)
        UI.setColor(b.color or { 0.78, 0.80, 0.84 })
        for i, line in ipairs(p.lines) do
          love.graphics.print(line, x + pad, y + p.y + (i - 1) * p.font:getHeight())
        end
      elseif b.kind == "save" then
        local cx, cy, cw, ch = x + pad, y + p.y, g.inner, 134
        UI.setColor({ 0.09, 0.10, 0.12 })
        love.graphics.rectangle("fill", cx, cy, cw, ch, 8, 8)
        love.graphics.setLineWidth(2)
        UI.setColor(b.badge and { 0.25, 0.70, 0.40 } or UI.colors.panelEdge)
        love.graphics.rectangle("line", cx, cy, cw, ch, 8, 8)
        UI.textClip(b.title, UI.sans(30), cx + 20, cy + 12, cw - 260, UI.colors.white)
        if b.badge then
          local bw = 170
          UI.setColor({ 0.33, 0.90, 0.53 })
          love.graphics.rectangle("fill", cx + cw - bw - 20, cy + 14, bw, 36, 18, 18)
          UI.textCentered(b.badge, UI.sans(22), cx + cw - bw - 20, cy + 14, bw, 36, { 0, 0, 0 })
        end
        local stats = b.stats or {}
        local colW = (cw - 40) / math.max(1, #stats)
        for i, st in ipairs(stats) do
          local sx = cx + 20 + (i - 1) * colW
          UI.textCentered(st[1], UI.sans(32), sx, cy + 54, colW, 40, UI.colors.white)
          UI.textCentered(st[2], UI.sans(22), sx, cy + 92, colW, 30, UI.colors.dim)
          if i > 1 then
            UI.setColor(UI.colors.panelEdge)
            love.graphics.line(sx, cy + 60, sx, cy + 120)
          end
        end
      end
    end
    for _, it in ipairs(items) do O.darkButton(it, it.id == focusId) end
  end

  function self:back() O.app.pop() return true end
  return self
end

---------------------------------------------------------------------------
-- Settings-style list: rows with < value > steppers, choice pairs or an
-- action button, scrolling, with buttons along the bottom.
-- specFn() returns { title, subtitle, rows = { row... }, footer = { btn... } }
--   row: { label, note, value = fn, step = fn(dir) }
--        { label, note, choices = { {value,label} }, selected = fn, select = fn(value) }
--        { label, note, action = { label, onPress, style } }
--        { heading = "Launcher Options", note = "Applies immediately" }
---------------------------------------------------------------------------
function O.settings(specFn)
  local self = { kind = "settings", scroll = 0 }
  local W, H = 1200, 1000
  local VIEW_TOP, FOOT_H = 150, 110

  local function rowHeight(r)
    if r.heading then return 90 end
    local h = r.choices and 150 or 104
    if r.note then
      h = h + #UI.wrap(UI.sans(22), r.note, W - 140) * UI.sans(22):getHeight() + 10
    end
    return h
  end

  function self:build()
    local spec = specFn()
    self._spec = spec
    local x, y = math.floor((UI.W - W) / 2), math.floor((UI.H - H) / 2)
    local viewY, viewH = y + VIEW_TOP, H - VIEW_TOP - FOOT_H
    local total = 0
    for _, r in ipairs(spec.rows) do total = total + rowHeight(r) end
    self.scroll = math.max(0, math.min(math.max(0, total - viewH), self.scroll))
    self._geo = { x = x, y = y, viewY = viewY, viewH = viewH }
    local clip = { x, viewY, W, viewH }
    local items = {}
    local cy = viewY - self.scroll
    self._rows = {}
    for i, r in ipairs(spec.rows) do
      local rh = rowHeight(r)
      self._rows[i] = { r = r, y = cy, h = rh }
      if not r.heading then
        local rx, rw = x + 40, W - 80
        if r.step then
          items[#items + 1] = { id = "s" .. i .. "_l", label = "<", rowIndex = i, clip = clip,
            x = rx + rw - 420, y = cy + 18, w = 72, h = 64, font = UI.sans(30),
            onPress = function() r.step(-1) end }
          items[#items + 1] = { id = "s" .. i .. "_r", label = ">", rowIndex = i, clip = clip,
            x = rx + rw - 90, y = cy + 18, w = 72, h = 64, font = UI.sans(30),
            onPress = function() r.step(1) end }
        elseif r.choices then
          local cw = (rw - 60) / #r.choices
          for c, ch in ipairs(r.choices) do
            items[#items + 1] = { id = "s" .. i .. "_c" .. c, label = ch.label, rowIndex = i, clip = clip,
              x = rx + 20 + (c - 1) * (cw + 20), y = cy + 66, w = cw - 20 + (c == #r.choices and 20 or 0),
              h = 64, style = r.selected() == ch.value and "blue" or "normal",
              onPress = function() r.select(ch.value) end }
          end
        elseif r.action then
          items[#items + 1] = { id = "s" .. i .. "_a", label = r.action.label, rowIndex = i, clip = clip,
            x = rx + rw - 200, y = cy + 18, w = 180, h = 64, style = r.action.style,
            onPress = r.action.onPress }
        end
      end
      cy = cy + rh
    end
    local fx = x + 40
    local fy = y + H - FOOT_H + 24
    local footer = spec.footer or {}
    local doneW = 220
    local restW = (W - 80 - doneW - 20)
    for i, f in ipairs(footer) do
      local isLast = i == #footer
      local fw = isLast and doneW or (restW - (#footer - 2) * 20) / math.max(1, #footer - 1)
      items[#items + 1] = { id = "f" .. i, label = f.label, style = f.style,
        x = fx, y = fy, w = fw, h = 66, onPress = f.onPress }
      fx = fx + fw + 20
    end
    return items
  end

  function self:onFocus(item)
    if not item.rowIndex or not self._rows then return end
    local row = self._rows[item.rowIndex]
    local g = self._geo
    if row.y < g.viewY then self.scroll = self.scroll - (g.viewY - row.y)
    elseif row.y + row.h > g.viewY + g.viewH then
      self.scroll = self.scroll + (row.y + row.h - (g.viewY + g.viewH))
    end
  end

  function self:wheel(dy) self.scroll = self.scroll - dy * 90 end

  -- Left / right on a < value > row changes the value straight away.
  function self:nav(dx, dy)
    if dx ~= 0 and self.focus and self._spec then
      local i = tostring(self.focus):match("^s(%d+)_[lr]$")
      local r = i and self._spec.rows[tonumber(i)]
      if r and r.step then r.step(dx) return true end
    end
    return false
  end

  function self:draw(items, focusId)
    dimBehind()
    local spec, g = self._spec, self._geo
    if not spec then return end
    UI.panel(g.x, g.y, W, H)
    UI.textClip(spec.title, UI.sans(48), g.x + 40, g.y + 30, W - 80, UI.colors.white)
    if spec.subtitle then
      UI.textClip(spec.subtitle, UI.sans(24), g.x + 40, g.y + 92, W - 80, UI.colors.dim)
    end
    love.graphics.setScissor(g.x, g.viewY, W, g.viewH)
    for _, row in ipairs(self._rows) do
      local r = row.r
      if row.y + row.h > g.viewY and row.y < g.viewY + g.viewH then
        if r.heading then
          UI.textClip(r.heading, UI.sans(30), g.x + 40, row.y + 14, W - 80, UI.colors.white)
          if r.note then UI.textClip(r.note, UI.sans(20), g.x + 40, row.y + 54, W - 80, UI.colors.dim) end
        else
          local bx, bw = g.x + 40, W - 80
          UI.setColor({ 0.10, 0.11, 0.13 })
          love.graphics.rectangle("fill", bx, row.y + 6, bw, row.h - 12, 8, 8)
          love.graphics.setLineWidth(2)
          UI.setColor(UI.colors.panelEdge)
          love.graphics.rectangle("line", bx, row.y + 6, bw, row.h - 12, 8, 8)
          UI.textClip(r.label, UI.sans(28), bx + 24, row.y + (r.choices and 22 or 32), bw - 480,
            r.disabled and UI.colors.dim or UI.colors.white)
          if r.value and not r.action and not r.choices then
            UI.setColor({ 0.07, 0.08, 0.09 })
            love.graphics.rectangle("fill", bx + bw - 348, row.y + 18, 258, 64)
            UI.textCentered(r.value(), UI.sans(28), bx + bw - 348, row.y + 18, 258, 64, UI.colors.white)
          end
          if r.note then
            love.graphics.setFont(UI.sans(22))
            UI.setColor(UI.colors.dim)
            local ny = row.y + (r.choices and 140 or 92)
            for i, line in ipairs(UI.wrap(UI.sans(22), r.note, bw - 60)) do
              love.graphics.print(line, bx + 24, ny + (i - 1) * UI.sans(22):getHeight())
            end
          end
        end
      end
    end
    for _, it in ipairs(items) do
      if it.rowIndex then O.darkButton(it, it.id == focusId) end
    end
    love.graphics.setScissor()
    UI.setColor(UI.colors.panelEdge)
    love.graphics.line(g.x + 40, g.y + H - FOOT_H + 6, g.x + W - 40, g.y + H - FOOT_H + 6)
    for _, it in ipairs(items) do
      if not it.rowIndex then O.darkButton(it, it.id == focusId) end
    end
  end

  function self:back() O.app.pop() return true end
  return self
end

return O
