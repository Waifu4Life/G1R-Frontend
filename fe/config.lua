-- The frontend's own settings, kept in its LOVE save folder (not Recomp's):
--   recompDir    folder holding the Gen1 Recomp program
--   art[game]    { kind = "box", file = "na_red_box.jpg" } or
--                { kind = "custom", file = "art/red.png" } or { kind = "none" }
--   cart[game]   custom cart id picked for that game (nil = the plain game)

local S = require("fe.serial")

local Config = { data = { art = {}, cart = {} } }
local FILE = "config.lua"

function Config.load()
  local body = love.filesystem.getInfo(FILE) and love.filesystem.read(FILE)
  local t = body and S.decodeLua(body)
  if type(t) == "table" then Config.data = t end
  Config.data.art = type(Config.data.art) == "table" and Config.data.art or {}
  Config.data.cart = type(Config.data.cart) == "table" and Config.data.cart or {}
  return Config.data
end

function Config.save()
  local ok = pcall(love.filesystem.write, FILE, S.encode(Config.data))
  return ok
end

function Config.get(key) return Config.data[key] end

function Config.set(key, value)
  Config.data[key] = value
  Config.save()
end

return Config
