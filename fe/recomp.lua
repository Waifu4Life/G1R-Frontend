-- Everything the frontend knows about a Gen1 Recomp install.
--
-- Three folders matter:
--   dir      the folder holding the Gen1 Recomp program
--   root     where Recomp keeps options.lua, saves/, mods/, carts/ -- the
--            program folder itself in portable mode (portable.txt), else
--            Recomp's OS data folder (identity "pokemon-love2d")
--   saveDir  Recomp's OS data folder, which always holds updates/
--
-- options.lua is shared with Recomp, which rewrites the whole file whenever
-- it saves settings. Every change here re-reads the file from disk, changes
-- only what it must, and writes it back the way Recomp does (.tmp, then .bak
-- of the previous file, then the file). A file that exists but can't be
-- read is never overwritten.

local FS = require("fe.nativefs")
local S = require("fe.serial")

local R = {}

-- love.filesystem.mount reports failure by returning false, not by erroring.
local function tryMount(...)
  local ok, result = pcall(love.filesystem.mount, ...)
  return ok and result == true
end

R.IDENTITY = "pokemon-love2d"

R.GAMES = {
  red       = { id = "red",       name = "Red",       gen = 1, suffix = "" },
  blue      = { id = "blue",      name = "Blue",      gen = 1, suffix = "_blue" },
  yellow    = { id = "yellow",    name = "Yellow",    gen = 1, suffix = "_yellow" },
  gold      = { id = "gold",      name = "Gold",      gen = 2, suffix = "_gold" },
  silver    = { id = "silver",    name = "Silver",    gen = 2, suffix = "_silver" },
  crystal   = { id = "crystal",   name = "Crystal",   gen = 2, suffix = "_crystal" },
  firered   = { id = "firered",   name = "FireRed",   gen = 3, suffix = "_firered" },
  leafgreen = { id = "leafgreen", name = "LeafGreen", gen = 3, suffix = "_leafgreen" },
  ruby      = { id = "ruby",      name = "Ruby",      gen = 3, suffix = "_ruby" },
  sapphire  = { id = "sapphire",  name = "Sapphire",  gen = 3, suffix = "_sapphire" },
  emerald   = { id = "emerald",   name = "Emerald",   gen = 3, suffix = "_emerald" },
}
R.ORDER = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }

R.dir, R.root, R.exe, R.saveDir = nil, nil, nil, nil

---------------------------------------------------------------------------
-- Finding the install
---------------------------------------------------------------------------
-- The Gen1 Recomp program inside a folder, or nil.
function R.findExe(dir)
  if not (dir and FS.isDir(dir)) then return nil end
  local items = FS.list(dir)
  if FS.windows then
    for _, it in ipairs(items) do
      if not it.dir and it.name:lower() == "gen1recomp.exe" then return FS.join(dir, it.name) end
    end
    for _, it in ipairs(items) do
      local n = it.name:lower()
      if not it.dir and n:match("^gen1recomp.*%.exe$") then return FS.join(dir, it.name) end
    end
    return nil
  end
  -- Linux: an AppImage or a plain program whose name mentions Recomp
  local best
  for _, it in ipairs(items) do
    local n = it.name:lower()
    if not it.dir and not n:find("frontend", 1, true)
        and (n:find("gen1recomp", 1, true) or n:find("g1r", 1, true)
        or n:find("recomp", 1, true)) then
      local e = FS.ext(n)
      if e == "appimage" then return FS.join(dir, it.name) end
      if not e or e == "x86_64" or e == "bin" or e == "sh" then best = best or FS.join(dir, it.name) end
    end
  end
  return best
end

local function firstExisting(list, file)
  for _, d in ipairs(list) do
    if FS.isFile(FS.join(d, file)) then return d end
  end
  for _, d in ipairs(list) do
    if FS.isDir(d) then return d end
  end
  return list[1]
end

function R.setup(dir)
  dir = FS.norm(dir)
  R._pointed = false
  R.dir = dir
  R.exe = R.findExe(dir)
  local saveDirs = FS.loveSaveDirs(R.IDENTITY)
  R.saveDir = firstExisting(saveDirs, "options.lua")
  if FS.isFile(FS.join(dir, "portable.txt")) then
    R.root = dir
    R.portable = true
  else
    R.root = R.saveDir
    R.portable = false
  end
  return R.exe ~= nil
end

function R.path(rel) return FS.join(R.root, rel) end

---------------------------------------------------------------------------
-- options.lua
---------------------------------------------------------------------------
local OPTIONS = "options.lua"

-- The current options table, or {} when there is no file yet.
-- Second value is an error when a file exists but couldn't be read.
function R.readOptions()
  local main = R.path(OPTIONS)
  local body = FS.read(main)
  if body and body ~= "" then
    local t, err = S.decodeLua(body)
    if t then return t end
    -- Recomp's own recovery order: .tmp, then .bak
    for _, alt in ipairs({ main .. ".tmp", main .. ".bak" }) do
      local t2 = S.decodeLua(FS.read(alt) or "")
      if t2 then return t2 end
    end
    return nil, "options.lua couldn't be read (" .. tostring(err) .. ")"
  end
  return {}
end

-- Read, change with fn(opts), write back. fn returns false to cancel.
function R.updateOptions(fn)
  local opts, err = R.readOptions()
  if not opts then return false, err end
  local result = fn(opts)
  if result == false then return false, "cancelled" end
  local encoded = S.encode(opts)
  local main = R.path(OPTIONS)
  local ok, werr = FS.write(main .. ".tmp", encoded)
  if not ok then return false, "couldn't write options (" .. tostring(werr) .. ")" end
  local prev = FS.read(main)
  if prev and prev ~= "" and prev ~= encoded then FS.write(main .. ".bak", prev) end
  ok, werr = FS.write(main, encoded)
  if not ok then return false, "couldn't write options (" .. tostring(werr) .. ")" end
  if FS.read(main) ~= encoded then return false, "options.lua didn't save correctly" end
  return true, result
end

---------------------------------------------------------------------------
-- Save slots (same layout as Recomp's SaveData)
--   game:  saves/<game>/slotN.lua, registry options.saveSlots[game]
--   cart:  saves/cart_<id>/slotN.lua, registry options.cartSlots[id]
-- Registry: { list = { "slot1", ... }, active = "slot2", names = { slot2 = "Nuzlocke" } }
---------------------------------------------------------------------------
local function scopeOf(gameId, cartId)
  if cartId then
    return { key = "cart_" .. cartId, rootKey = "cartSlots", id = cartId,
             legacy = "save_cart_" .. cartId .. ".lua" }
  end
  local g = R.GAMES[gameId]
  return { key = gameId, rootKey = "saveSlots", id = gameId,
           legacy = "save" .. (g and g.suffix or ("_" .. gameId)) .. ".lua" }
end

local function registryIn(opts, scope)
  local root = opts[scope.rootKey]
  local reg = type(root) == "table" and root[scope.id] or nil
  return type(reg) == "table" and reg or nil
end

local function countTrue(t)
  local n = 0
  if type(t) == "table" then for _, v in pairs(t) do if v then n = n + 1 end end end
  return n
end

local GEN1_BADGES = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
  "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE" }

-- Name, badges, play time and Pokedex count, like Recomp's save list.
function R.summarize(save, gen)
  if type(save) ~= "table" then return nil end
  local p = type(save.player) == "table" and save.player or {}
  local name = p.name or save.name or save.playerName
  local dex, badges = 0, nil
  if gen == 1 then
    dex = countTrue(save.pokedex and save.pokedex.owned)
    badges = 0
    local inv = type(save.inventory) == "table" and save.inventory or {}
    for _, b in ipairs(GEN1_BADGES) do if inv[b] then badges = badges + 1 end end
  elseif gen == 2 then
    dex = countTrue(save.pokedex and save.pokedex.caught)
    badges = countTrue(p.badges) + countTrue(p.kantoBadges)
  else
    local list = save.badges or p.badges
    if type(list) == "table" then badges = countTrue(list) end
  end
  local pt = save.playTime or save.playtime or p.playtime
  local secs
  if type(pt) == "table" then
    secs = (tonumber(pt.hours) or 0) * 3600 + (tonumber(pt.minutes) or 0) * 60
      + (tonumber(pt.seconds) or 0)
  else
    secs = math.floor(tonumber(pt) or 0)
  end
  local time = ("%d:%02d"):format(math.floor(secs / 3600), math.floor(secs / 60) % 60)
  return { name = type(name) == "string" and name or nil, badges = badges,
           time = time, dex = dex }
end

local function readSlotSave(scope, slotId)
  local main = R.path("saves/" .. scope.key .. "/" .. slotId .. ".lua")
  for _, p in ipairs({ main, main .. ".tmp", main .. ".bak" }) do
    local body = FS.read(p)
    if body then
      local t = S.decodeLua(body)
      if t then return t end
    end
  end
  return nil
end

-- Everything the Saves menu needs for one game (or one cart).
-- { slots = { {id, label, exists, summary, active}, ... }, active = id,
--   needsRecomp = "why" when Recomp has to sort this game's saves out first }
function R.listSlots(gameId, cartId)
  local scope = scopeOf(gameId, cartId)
  local opts, err = R.readOptions()
  if not opts then return { slots = {}, error = err } end
  local reg = registryIn(opts, scope)
  local list = reg and type(reg.list) == "table" and reg.list or {}
  local info = { slots = {}, scope = scope }
  if #list == 0 then
    -- Recomp moves an old single save into slot 1, or rebuilds a lost list,
    -- the first time it opens this game. Leave that to Recomp.
    if FS.isFile(R.path(scope.legacy)) or FS.isFile(R.path(scope.legacy .. ".bak")) then
      info.needsRecomp = "This game still has its save in Gen1 Recomp's older format. " ..
        "Play it once (or open it in Gen1 Recomp) so Recomp can move it into the save list."
    elseif FS.isDir(R.path("saves/" .. scope.key)) and #FS.list(R.path("saves/" .. scope.key)) > 0 then
      info.needsRecomp = "Gen1 Recomp needs to rebuild this game's save list. " ..
        "Play it once (or open it in Gen1 Recomp) first."
    end
    return info
  end
  local active = reg.active or list[1]
  info.active = active
  local gen = R.GAMES[gameId] and R.GAMES[gameId].gen or 1
  for _, id in ipairs(list) do
    local save = readSlotSave(scope, id)
    info.slots[#info.slots + 1] = {
      id = id,
      label = type(reg.names) == "table" and reg.names[id] or nil,
      exists = save ~= nil,
      summary = R.summarize(save, gen),
      active = id == active,
    }
  end
  return info
end

function R.slotTitle(slot)
  if slot.label then return slot.label end
  if slot.summary and slot.summary.name then return slot.summary.name end
  if not slot.exists then return "NEW GAME" end
  return slot.id
end

function R.slotDetail(slot)
  if not (slot.exists and slot.summary) then return "empty save" end
  local s = slot.summary
  local parts = {}
  if s.badges then parts[#parts + 1] = s.badges .. " badges" end
  parts[#parts + 1] = s.time
  parts[#parts + 1] = (s.dex or 0) .. " caught"
  return table.concat(parts, " - ")
end

local function withRegistry(gameId, cartId, fn)
  local scope = scopeOf(gameId, cartId)
  return R.updateOptions(function(opts)
    opts[scope.rootKey] = type(opts[scope.rootKey]) == "table" and opts[scope.rootKey] or {}
    local reg = opts[scope.rootKey][scope.id]
    if type(reg) ~= "table" then reg = { list = {} } end
    reg.list = type(reg.list) == "table" and reg.list or {}
    local result = fn(reg, opts)
    if result == false then return false end
    opts[scope.rootKey][scope.id] = reg
    return result
  end)
end

function R.setActiveSlot(gameId, cartId, slotId)
  return withRegistry(gameId, cartId, function(reg)
    local found = false
    for _, id in ipairs(reg.list) do if id == slotId then found = true end end
    if not found then reg.list[#reg.list + 1] = slotId end
    reg.active = slotId
  end)
end

-- A new empty save, made the active one so the next launch starts it.
function R.createSlot(gameId, cartId)
  local info = R.listSlots(gameId, cartId)
  if info.needsRecomp then return false, info.needsRecomp end
  return withRegistry(gameId, cartId, function(reg)
    local maxN = 0
    for _, id in ipairs(reg.list) do
      local n = tonumber(tostring(id):match("^slot(%d+)$"))
      if n and n > maxN then maxN = n end
    end
    -- never reuse a number that still has a file on disk
    local scope = scopeOf(gameId, cartId)
    local n = maxN + 1
    while FS.isFile(R.path("saves/" .. scope.key .. "/slot" .. n .. ".lua")) do n = n + 1 end
    local id = "slot" .. n
    reg.list[#reg.list + 1] = id
    reg.active = id
    return id
  end)
end

function R.renameSlot(gameId, cartId, slotId, name)
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or nil
  if name == "" then name = nil end
  return withRegistry(gameId, cartId, function(reg)
    local found = false
    for _, id in ipairs(reg.list) do if id == slotId then found = true end end
    if not found then return false end
    reg.names = type(reg.names) == "table" and reg.names or {}
    reg.names[slotId] = name
    if next(reg.names) == nil then reg.names = nil end
  end)
end

---------------------------------------------------------------------------
-- Custom carts: carts/<id>.g1rcart, registered in options.carts[id]
---------------------------------------------------------------------------
function R.listCarts(gameId)
  local opts = R.readOptions() or {}
  local out = {}
  if type(opts.carts) == "table" then
    for id, rec in pairs(opts.carts) do
      if type(rec) == "table" and (gameId == nil or rec.base == gameId) then
        out[#out + 1] = { id = id, title = rec.title or id, author = rec.author,
          version = rec.version, base = rec.base, summary = rec.summary,
          present = FS.isFile(R.path("carts/" .. id .. ".g1rcart")) }
      end
    end
  end
  table.sort(out, function(a, b) return tostring(a.title):lower() < tostring(b.title):lower() end)
  return out
end

---------------------------------------------------------------------------
-- Mods: mods/<folder>/manifest.json
---------------------------------------------------------------------------
local GEN_GAMES = {
  gen1 = { "red", "blue", "yellow" },
  gen2 = { "gold", "silver", "crystal" },
  gen3 = { "firered", "leafgreen", "ruby", "sapphire", "emerald" },
}

local function gamesFor(manifest)
  local claim = manifest.games
  if type(claim) == "string" then claim = { claim } end
  if type(claim) ~= "table" or #claim == 0 then return R.ORDER end
  local set, out = {}, {}
  for _, g in ipairs(claim) do
    g = tostring(g):lower()
    if g == "all" or g == "*" then return R.ORDER end
    for _, id in ipairs(GEN_GAMES[g] or { g }) do
      if R.GAMES[id] and not set[id] then set[id] = true end
    end
  end
  for _, id in ipairs(R.ORDER) do if set[id] then out[#out + 1] = id end end
  return out
end

function R.listMods()
  local out = {}
  local dir = R.path("mods")
  if not FS.isDir(dir) then return out end
  for _, it in ipairs(FS.list(dir)) do
    if it.dir then
      local mdir = FS.join(dir, it.name)
      local m = S.decodeJson(FS.read(FS.join(mdir, "manifest.json")) or "")
      if type(m) == "table" and type(m.id) == "string" and m.id ~= "" then
        out[#out + 1] = {
          id = m.id, name = m.name or m.id, version = m.version or "?",
          category = m.category,
          description = tostring(m.description or ""):gsub("%s+", " "),
          author = m.author or m.authors, games = gamesFor(m),
          gameClaim = m.games, experimental = m.experimental == true,
          folder = it.name, dir = mdir, manifest = m,
        }
      end
    end
  end
  return out
end

-- true/false for one mod on one game, using Recomp's rules: the game's own
-- answer, else the shared answer, else on (off for experimental mods).
function R.modEnabled(opts, mod, gameId)
  local byV = opts.modsByVersion
  local bucket = type(byV) == "table" and byV[gameId] or nil
  if type(bucket) == "table" and type(bucket[mod.id]) == "boolean" then return bucket[mod.id] end
  local shared = type(opts.mods) == "table" and opts.mods[mod.id]
  if type(shared) == "boolean" then return shared end
  return not mod.experimental
end

-- Recomp copies every mod's old shared answer to each game once before
-- per-game answers start. Do the same before writing one.
local function migrateMods(opts, mods)
  if opts.modsByVersionMigrated then return end
  opts.mods = type(opts.mods) == "table" and opts.mods or {}
  opts.modsByVersion = type(opts.modsByVersion) == "table" and opts.modsByVersion or {}
  local known = {}
  for id in pairs(opts.mods) do if type(id) == "string" then known[id] = { id = id } end end
  for v, bucket in pairs(opts.modsByVersion) do
    if R.GAMES[v] and type(bucket) == "table" then
      for id in pairs(bucket) do known[id] = known[id] or { id = id } end
    end
  end
  for _, m in ipairs(mods) do known[m.id] = m end
  if next(known) == nil then return end
  for id, m in pairs(known) do
    local shared = opts.mods[id]
    if type(shared) ~= "boolean" then shared = not (m.experimental == true) end
    for _, v in ipairs(R.ORDER) do
      local bucket = opts.modsByVersion[v]
      if type(bucket) ~= "table" then bucket = {}; opts.modsByVersion[v] = bucket end
      if type(bucket[id]) ~= "boolean" then bucket[id] = shared end
    end
  end
  opts.modsByVersionMigrated = true
end

-- Turn mods on/off for a list of games. changes = { { mod, gameId, value }, ... }
function R.setModsEnabled(changes, allMods)
  return R.updateOptions(function(opts)
    migrateMods(opts, allMods or {})
    opts.modsByVersion = type(opts.modsByVersion) == "table" and opts.modsByVersion or {}
    for _, ch in ipairs(changes) do
      local bucket = opts.modsByVersion[ch[2]]
      if type(bucket) ~= "table" then bucket = {}; opts.modsByVersion[ch[2]] = bucket end
      local shared = type(opts.mods) == "table" and opts.mods[ch[1].id]
      if type(shared) == "boolean" and shared == ch[3] then
        bucket[ch[1].id] = nil
      else
        bucket[ch[1].id] = ch[3] and true or false
      end
    end
  end)
end

-- Install (or update) a mod from a .zip on disk. Returns ok, message.
function R.installModZip(zipPath)
  local bytes = FS.read(zipPath)
  if not bytes then return false, "Couldn't read " .. FS.basename(zipPath) end
  local okData, fd = pcall(love.filesystem.newFileData, bytes, "import.zip")
  if not okData then return false, "Couldn't open the zip" end
  local mountPoint = "fe_zip_" .. tostring(os.time())
  pcall(love.filesystem.unmount, "import.zip")
  local okMount = tryMount(fd, "import.zip", mountPoint)
  if not okMount then return false, "That file isn't a zip Gen1 Recomp can use" end
  local lf = love.filesystem
  -- the manifest sits at the top, or inside a single top folder
  local base
  if lf.getInfo(mountPoint .. "/manifest.json") then
    base = mountPoint
  else
    for _, name in ipairs(lf.getDirectoryItems(mountPoint)) do
      local p = mountPoint .. "/" .. name
      if lf.getInfo(p .. "/manifest.json") then base = p break end
    end
  end
  if not base then
    pcall(lf.unmount, fd)
    pcall(lf.unmount, "import.zip")
    return false, "No manifest.json in that zip, so it isn't a Gen1 Recomp mod"
  end
  local m = S.decodeJson(lf.read(base .. "/manifest.json") or "")
  if type(m) ~= "table" or type(m.id) ~= "string" or not m.id:match("^[%w_%-%.]+$") then
    pcall(lf.unmount, fd)
    pcall(lf.unmount, "import.zip")
    return false, "The mod's manifest.json has no usable id"
  end
  local target = R.path("mods/" .. m.id)
  if not FS.mkdirp(target) then
    pcall(lf.unmount, fd)
    pcall(lf.unmount, "import.zip")
    return false, "Couldn't create " .. target
  end
  local count, failed = 0, nil
  local function copyTree(src, dst)
    for _, name in ipairs(lf.getDirectoryItems(src)) do
      local s, d = src .. "/" .. name, dst .. "/" .. name
      local info = lf.getInfo(s)
      if info and info.type == "directory" then
        FS.mkdirp(d)
        copyTree(s, d)
      elseif info then
        local data = lf.read(s)
        if data and FS.write(d, data) then count = count + 1 else failed = failed or name end
      end
    end
  end
  copyTree(base, target)
  pcall(lf.unmount, fd)
  pcall(lf.unmount, "import.zip")
  if failed then return false, "Some files couldn't be copied (" .. failed .. ")" end
  return true, ("Installed %s %s (%d files)"):format(m.name or m.id, tostring(m.version or ""), count)
end

---------------------------------------------------------------------------
-- Companion mod (bundled in the frontend): lets a game started from the
-- frontend close Gen1 Recomp when its window is closed, instead of
-- reopening Recomp's launcher.
---------------------------------------------------------------------------
local COMPANION = "g1r_frontend_companion"

function R.installCompanion()
  if not R.root then return false end
  local dir = R.path("mods/" .. COMPANION)
  local want = love.filesystem.read("companion/manifest.json")
  if not want then return false end
  if FS.read(FS.join(dir, "manifest.json")) == want then return true end
  if not FS.mkdirp(dir) then return false end
  FS.write(FS.join(dir, "main.lua"), love.filesystem.read("companion/main.lua") or "")
  return FS.write(FS.join(dir, "manifest.json"), want)
end

local function markSession()
  if not R.root then return end
  local dir = R.path("mods/" .. COMPANION)
  if FS.isDir(dir) then FS.write(FS.join(dir, "session.txt"), tostring(os.time()) .. "\n") end
end

---------------------------------------------------------------------------
-- Launching
---------------------------------------------------------------------------
function R.launch(gameId, cartId)
  if not R.exe then return false, "Gen1 Recomp's program wasn't found in " .. tostring(R.dir) end
  if gameId then markSession() end
  local args = {}
  if gameId then args[#args + 1] = "--game=" .. gameId end
  if cartId then args[#args + 1] = "--cart=" .. cartId end
  return FS.launch(R.exe, args, R.dir)
end

-- Gen1 Recomp's save editor on the game's loaded save (its standalone
-- mode: --editor, with the game picked by POKEPORT_VERSION).
function R.editSave(gameId, cartId, slotId)
  if not R.exe then return false, "Gen1 Recomp's program wasn't found" end
  local key = cartId and ("cart_" .. cartId) or gameId
  local path = R.path("saves/" .. key .. "/" .. slotId .. ".lua")
  if not FS.isFile(path) then return false, "That save's file wasn't found:\n" .. path end
  if FS.windows then path = FS.winPath(path) end
  return FS.launch(R.exe, { "--editor", "--save", path }, R.dir, { POKEPORT_VERSION = gameId })
end

-- Open Recomp's launcher on one of its own tabs ("box", "online", "skins",
-- "mods", "importers"). Recomp reads this hand-off file once at start-up.
function R.openLauncherTab(tab)
  if not R.exe then return false, "Gen1 Recomp's program wasn't found" end
  if R.saveDir and FS.mkdirp(R.saveDir) then
    FS.write(FS.join(R.saveDir, "relaunch_to_launcher.txt"), S.encode({ tab = tab }))
  end
  return FS.launch(R.exe, {}, R.dir)
end

-- Gen1 Recomp's own Settings model (the gear menu) for one game, so the
-- frontend shows every row Recomp has, mods' options included.
function R.settingsModel(version, hooks)
  local ok, model = R.withRecomp(version, function()
    return require("src.import.LauncherSettings").open(hooks or {}, version)
  end)
  if ok and type(model) == "table" then return model end
  return nil, model
end

-- Open Recomp's own launcher on a game's tab (for things only it can do).
function R.openLauncherOn(gameId)
  if not R.exe then return false, "Gen1 Recomp's program wasn't found" end
  return FS.launch(R.exe, { "--game=" .. gameId, "--launcher" }, R.dir)
end

---------------------------------------------------------------------------
-- Versions and updates (payloads live in <saveDir>/updates)
---------------------------------------------------------------------------
function R.parseVersion(v)
  local a, b, c = tostring(v or ""):match("(%d+)[%._](%d+)[%._](%d+)")
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) }
end

function R.compareVersions(x, y)
  local a, b = R.parseVersion(x), R.parseVersion(y)
  if not a or not b then return 0 end
  for i = 1, 3 do
    if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
  end
  return 0
end

-- The newest downloaded update payload's version, or nil.
function R.installedVersion()
  local best
  local dir = R.saveDir and FS.join(R.saveDir, "updates")
  if dir and FS.isDir(dir) then
    for _, it in ipairs(FS.list(dir)) do
      local v = it.name:match("^gen1recomp%-(.+)%.love$")
      if v and R.parseVersion(v) and (not best or R.compareVersions(v, best) > 0) then best = v end
    end
  end
  return best
end

function R.updatesDir()
  return R.saveDir and FS.join(R.saveDir, "updates")
end

---------------------------------------------------------------------------
-- Save import, using Gen1 Recomp's own converter.
-- Recomp's code is loaded from its newest update payload (or the program
-- itself on Windows) and pointed at its own folder, so the import is done
-- exactly the way the Recomp launcher does it. Portable installs only.
---------------------------------------------------------------------------
local mounted = false

local function mountRecompCode()
  if mounted then return true end
  local candidates = {}
  local v = R.installedVersion()
  if v then candidates[#candidates + 1] = FS.join(R.updatesDir(), "gen1recomp-" .. v .. ".love") end
  if R.exe and FS.windows then candidates[#candidates + 1] = R.exe end
  for _, path in ipairs(candidates) do
    local bytes = FS.read(path)
    if bytes then
      local ok, fd = pcall(love.filesystem.newFileData, bytes, "g1r_code.zip")
      local mountedOk = ok and (tryMount(fd, "g1r_code.zip", "/", true)
        or tryMount(fd, "g1r_code.zip", "", true))
      if mountedOk and love.filesystem.getInfo("src/core/SaveData.lua") then
        R._codeData = fd
        mounted = true
        return true
      end
    end
  end
  return false
end

-- Run fn with Gen1 Recomp's own save code, pointed at Recomp's folder.
-- Returns ok, results... ; ok=false plus a message (and fallback=true when
-- Recomp's launcher should be used instead).
function R.withRecomp(gameId, fn)
  if not R.portable then
    return false, "This needs a portable Gen1 Recomp install.", true
  end
  if not mountRecompCode() then
    return false, "Gen1 Recomp's code couldn't be loaded.", true
  end
  local results = { pcall(function()
    local SaveData = require("src.core.SaveData")
    if not R._pointed then
      SaveData.gameFolders = function() return { R.root } end
      if SaveData._resetPortableCacheForTests then SaveData._resetPortableCacheForTests() end
      R._pointed = true
    end
    -- the frontend may have changed files since the last call
    if SaveData.invalidateOptionsCache then SaveData.invalidateOptionsCache() end
    if SaveData.resetSlotState then SaveData.resetSlotState() end
    local GameVersion = require("src.core.GameVersion")
    if gameId and R.GAMES[gameId] then GameVersion.set(gameId) end
    return fn(SaveData, GameVersion)
  end) }
  if not results[1] then
    return false, "Gen1 Recomp's code stopped: " .. tostring(results[2]), true
  end
  return true, unpack(results, 2, table.maxn(results))
end

function R.importSave(gameId, savPath)
  local ok, a, b = R.withRecomp(gameId, function()
    local SaveFileIO = require("src.import.SaveFileIO")
    return SaveFileIO.importToSlot(savPath, gameId, true)
  end)
  if not ok then return false, a, b end
  if a then return true, "Save imported and selected." end
  return false, tostring(b or "Import failed.")
end

function R.exportSave(gameId)
  local ok, a, b = R.withRecomp(gameId, function()
    local SaveFileIO = require("src.import.SaveFileIO")
    return SaveFileIO.exportActiveSlot(gameId)
  end)
  if not ok then return false, a, b end
  if a then return true, tostring(b) end
  return false, tostring(b or "Export failed.")
end

function R.duplicateSlot(gameId, cartId, slotId)
  local ok, id, err = R.withRecomp(gameId, function(SaveData)
    if cartId then return SaveData.duplicateCartSlot(cartId, slotId) end
    return SaveData.duplicateSlot(gameId, slotId)
  end)
  if not ok then return false, id, err end
  if id then return true, id end
  return false, tostring(err or "Duplicate failed.")
end

function R.deleteSlot(gameId, cartId, slotId)
  local ok, done, err = R.withRecomp(gameId, function(SaveData)
    if cartId then return SaveData.deleteCartSlot(cartId, slotId) end
    return SaveData.deleteSlot(gameId, slotId)
  end)
  if not ok then return false, done, err end
  if done ~= false and done ~= nil then return true end
  return false, tostring(err or "Delete failed.")
end

-- ID Sync step 1: the trainer on the chosen save, { name, id } or nil, why.
function R.idSyncProfile(gameId, cartId, slotId)
  local ok, profile, why = R.withRecomp(gameId, function(SaveData)
    local TrainerIdSync = require("src.core.TrainerIdSync")
    local source = cartId and SaveData.readCartSlotSource(cartId, slotId)
      or SaveData.readSlotSource(gameId, slotId)
    local save = source and SaveData.decode(source)
    if not save then return nil, "That save couldn't be read." end
    local p = require("src.core.TrainerIdentity").profile(save,
      TrainerIdSync.generationOf(save, gameId))
    if not p then return nil, "This save needs a trainer name and ID before it can sync." end
    return { name = p.name, id = p.id }
  end)
  if not ok then return nil, profile, why end
  return profile, why
end

-- ID Sync step 2: a job to call :step() on until it says it's done.
function R.idSyncJob(gameId, cartId, slotId)
  local ok, job = R.withRecomp(gameId, function()
    local TrainerIdSync = require("src.core.TrainerIdSync")
    return TrainerIdSync.newJob({ scope = cartId and ("cart_" .. cartId) or gameId, slot = slotId })
  end)
  if not ok then return nil, job end
  return job
end

---------------------------------------------------------------------------
-- Mod load order (options.modOrder) and removal
---------------------------------------------------------------------------
local function priorityOf(m)
  return tonumber(m.manifest and m.manifest.priority) or 0
end

-- Every installed mod id in load order: the saved order first, then the
-- rest by priority, slotted in the way Recomp's LoadOrder does it.
function R.loadOrder(opts, mods)
  local saved, seen = {}, {}
  for _, id in ipairs(type(opts.modOrder) == "table" and opts.modOrder or {}) do
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      saved[#saved + 1] = id
    end
  end
  local prio = {}
  for _, m in ipairs(mods) do prio[m.id] = priorityOf(m) end
  local rest = {}
  for _, m in ipairs(mods) do if not seen[m.id] then rest[#rest + 1] = m end end
  table.sort(rest, function(a, b)
    local pa, pb = priorityOf(a), priorityOf(b)
    if pa == pb then return a.id < b.id end
    return pa < pb
  end)
  local out, t = {}, 1
  for _, id in ipairs(saved) do
    local p = prio[id]
    if p then
      while rest[t] and priorityOf(rest[t]) < p do
        out[#out + 1] = rest[t].id
        t = t + 1
      end
    end
    out[#out + 1] = id
  end
  for i = t, #rest do out[#out + 1] = rest[i].id end
  return out
end

-- where = -1 / 1 (one step), "top" or "bottom"
function R.moveMod(id, where, mods)
  return R.updateOptions(function(opts)
    local order = R.loadOrder(opts, mods)
    local at
    for i, v in ipairs(order) do if v == id then at = i end end
    if not at then return false end
    local to
    if where == "top" then to = 1
    elseif where == "bottom" then to = #order
    else to = math.max(1, math.min(#order, at + where)) end
    if to == at then return false end
    table.remove(order, at)
    table.insert(order, to, id)
    opts.modOrder = order
  end)
end

function R.deleteMod(mod)
  if not (mod and mod.dir) or not mod.dir:find(R.path("mods"), 1, true) then
    return false, "That mod isn't in Gen1 Recomp's mods folder."
  end
  FS.removeTree(mod.dir)
  if FS.isDir(mod.dir) then return false, "Some files couldn't be deleted (is Gen1 Recomp open?)" end
  return true
end

-- { { id, need = "required"/"optional", have = version or nil, range } }
function R.modDependencies(mod, mods)
  local byId = {}
  for _, m in ipairs(mods) do byId[m.id] = m end
  local out = {}
  local function add(list, need)
    for _, d in ipairs(type(list) == "table" and list or {}) do
      local id, range
      if type(d) == "string" then
        id, range = d:match("^%s*([^%s@<>=~^]+)%s*@?%s*(.-)%s*$")
      elseif type(d) == "table" then
        id, range = d.id, d.version or d.range
      end
      if id and id ~= "" then
        local m = byId[id]
        out[#out + 1] = { id = id, need = need, range = range ~= "" and range or nil,
          have = m and m.version or nil, name = m and m.name or id }
      end
    end
  end
  add(mod.manifest.dependencies, "required")
  add(mod.manifest.optional_dependencies, "optional")
  return out
end

-- Save Sync status from options.saveSync (set up by Gen1 Recomp).
function R.syncStatus()
  local opts = R.readOptions() or {}
  local st = type(opts.saveSync) == "table" and opts.saveSync or {}
  if type(st.deviceToken) == "string" and st.deviceToken ~= "" then
    local who = st.displayName or st.account or "your account"
    local when = tonumber(st.lastSyncAt) or 0
    local last = when > 0 and os.date("%Y-%m-%d %H:%M", when) or "never"
    return ("Linked to %s%s. Last sync: %s"):format(tostring(who),
      st.enabled == true and "" or " (paused)", last), true
  end
  return "Not set up", false
end

return R
