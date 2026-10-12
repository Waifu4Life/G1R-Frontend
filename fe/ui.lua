-- Drawing helpers shared by every screen.
-- Everything is laid out on a 1920x1080 canvas that main.lua scales to the
-- window, so positions here are in those "design pixels".

local UI = {}

UI.W, UI.H = 1920, 1080

UI.colors = {
  bg        = { 0, 0, 0 },
  white     = { 1, 1, 1 },
  text      = { 0.05, 0.05, 0.05 },
  tab       = { 0.94, 0.89, 0.69 },   -- cream
  tabActive = { 0.62, 0.86, 0.93 },   -- light blue
  tabBorder = { 1.00, 0.93, 0.10 },   -- yellow
  red       = { 0.93, 0.12, 0.14 },
  art       = { 1.00, 0.70, 0.79 },   -- pink
  saves     = { 1.00, 0.79, 0.05 },   -- amber
  rename    = { 0.76, 0.76, 0.76 },   -- grey
  import    = { 0.79, 0.75, 0.90 },   -- lavender
  carts     = { 0.74, 0.49, 0.36 },   -- brown
  green     = { 0.72, 0.90, 0.13 },
  greenEdge = { 0.25, 0.75, 0.20 },
  focus     = { 0.20, 0.85, 1.00 },
  panel     = { 0.11, 0.13, 0.16 },
  panel2    = { 0.16, 0.18, 0.22 },
  panelEdge = { 0.30, 0.33, 0.38 },
  dim       = { 0.60, 0.63, 0.68 },
  ok        = { 0.35, 0.85, 0.45 },
  warn      = { 1.00, 0.85, 0.20 },
  blue      = { 0.20, 0.45, 0.85 },
}

local fontCache = {}
function UI.pixel(size)
  local key = "p" .. size
  if not fontCache[key] then
    local ok, f = pcall(love.graphics.newFont, "assets/fonts/PlainPixel-Regular.ttf", size)
    if not ok then f = love.graphics.newFont(size) end
    f:setFilter("nearest", "nearest")
    fontCache[key] = f
  end
  return fontCache[key]
end

function UI.sans(size)
  local key = "s" .. size
  if not fontCache[key] then fontCache[key] = love.graphics.newFont(size) end
  return fontCache[key]
end

function UI.setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

-- Text centred in a box, squeezed sideways if it's too wide.
function UI.textCentered(text, font, x, y, w, h, color)
  text = tostring(text or "")
  love.graphics.setFont(font)
  local tw, th = font:getWidth(text), font:getHeight()
  local sx = 1
  if tw > w - 16 and tw > 0 then sx = (w - 16) / tw end
  UI.setColor(color or UI.colors.text)
  love.graphics.print(text, math.floor(x + (w - tw * sx) / 2), math.floor(y + (h - th) / 2), 0, sx, 1)
end

-- Text left-aligned on one line, cut with "..." when too wide.
function UI.textClip(text, font, x, y, w, color)
  text = tostring(text or "")
  love.graphics.setFont(font)
  if font:getWidth(text) > w then
    while #text > 1 and font:getWidth(text .. "...") > w do
      text = text:sub(1, #text - 1)
    end
    text = text .. "..."
  end
  UI.setColor(color or UI.colors.white)
  love.graphics.print(text, math.floor(x), math.floor(y))
end

-- The rounded, outlined buttons from the mock-ups.
function UI.button(item, focused)
  local x, y, w, h = item.x, item.y, item.w, item.h
  local fill = item.fill or UI.colors.tab
  local edge = item.edge or UI.colors.red
  local alpha = item.disabled and 0.35 or 1
  love.graphics.setLineWidth(4)
  UI.setColor(fill, alpha)
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  UI.setColor(edge, alpha)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
  local tc = item.textColor or UI.colors.text
  UI.textCentered(item.label, item.font or UI.pixel(33), x, y, w, h,
    { tc[1], tc[2], tc[3], alpha })
  if focused then UI.focusRing(item) end
end

function UI.focusRing(item, pad)
  pad = pad or 6
  local t = love.timer.getTime()
  local pulse = 0.65 + 0.35 * math.sin(t * 6)
  love.graphics.setLineWidth(5)
  UI.setColor(UI.colors.focus, pulse)
  love.graphics.rectangle("line", item.x - pad, item.y - pad, item.w + pad * 2,
    item.h + pad * 2, 14, 14)
  love.graphics.setLineWidth(1)
end

-- An image fitted inside a box without stretching.
function UI.imageContain(img, x, y, w, h)
  local iw, ih = img:getDimensions()
  local s = math.min(w / iw, h / ih)
  local dw, dh = iw * s, ih * s
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x + (w - dw) / 2, y + (h - dh) / 2, 0, s, s)
end

-- A dark panel, used by menus and the Mods tab.
function UI.panel(x, y, w, h)
  UI.setColor(UI.colors.panel, 0.98)
  love.graphics.rectangle("fill", x, y, w, h, 12, 12)
  love.graphics.setLineWidth(2)
  UI.setColor(UI.colors.panelEdge)
  love.graphics.rectangle("line", x, y, w, h, 12, 12)
  love.graphics.setLineWidth(1)
end

-- Wrap text into lines that fit a width.
function UI.wrap(font, text, width)
  local _, lines = font:getWrap(tostring(text or ""), width)
  return lines
end

---------------------------------------------------------------------------
-- Focus movement between the items on screen (arrow keys / D-pad).
-- Picks the nearest item in the pressed direction, favouring items that
-- line up with the current one.
---------------------------------------------------------------------------
function UI.findItem(items, id)
  for _, it in ipairs(items) do if it.id == id then return it end end
  return nil
end

function UI.firstFocusable(items)
  for _, it in ipairs(items) do if not it.noFocus then return it end end
  return nil
end

function UI.moveFocus(items, curId, dx, dy)
  local cur = UI.findItem(items, curId)
  if not cur or cur.noFocus then
    local first = UI.firstFocusable(items)
    return first and first.id or nil
  end
  local cx, cy = cur.x + cur.w / 2, cur.y + cur.h / 2
  local best, bestScore
  for _, it in ipairs(items) do
    if it ~= cur and not it.noFocus then
      local ix, iy = it.x + it.w / 2, it.y + it.h / 2
      local primary, secondary
      if dx ~= 0 then
        primary = (ix - cx) * dx
        -- overlap on the other axis counts as perfectly lined up
        local overlap = math.min(cur.y + cur.h, it.y + it.h) - math.max(cur.y, it.y)
        secondary = overlap > 0 and 0 or math.abs(iy - cy)
      else
        primary = (iy - cy) * dy
        local overlap = math.min(cur.x + cur.w, it.x + it.w) - math.max(cur.x, it.x)
        secondary = overlap > 0 and math.abs(ix - cx) * 0.2 or math.abs(ix - cx)
      end
      if primary > 4 then
        local score = primary + secondary * 2.5
        if not bestScore or score < bestScore then best, bestScore = it, score end
      end
    end
  end
  return best and best.id or curId
end

function UI.hit(items, mx, my)
  for i = #items, 1, -1 do
    local it = items[i]
    if not it.noFocus and mx >= it.x and mx <= it.x + it.w and my >= it.y and my <= it.y + it.h then
      local c = it.clip
      if not c or (mx >= c[1] and mx <= c[1] + c[3] and my >= c[2] and my <= c[2] + c[4]) then
        return it
      end
    end
  end
  return nil
end

return UI
