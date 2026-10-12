-- The main screen: the five tabs along the top, the game cards (each with
-- its save under it and a Menu drop-down), the Mods tab, and the bar along
-- the bottom.

local UI = require("fe.ui")
local FS = require("fe.nativefs")
local R = require("fe.recomp")
local O = require("fe.overlays")
local Catalog = require("fe.catalog")
local Config = require("fe.config")
local S = require("fe.serial")

local M = { activeTab = 1, focus = "tab1", modScroll = 0, modFilter = "all", modSort = "order",
            menuOpen = nil }
local App   -- set by M.init

local images = {}      -- game id -> Image or false
local saveInfo = {}    -- game id -> { lines = { ... } }
local mods, modOpts, modOrder = {}, {}, {}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function artFor(game)
  local choice = Config.data.art[game.id]
  if type(choice) ~= "table" then
    choice = { kind = "box", file = game.boxes[1] and game.boxes[1][2] }
  end
  return choice
end

local function loadImage(game)
  local choice = artFor(game)
  local img = false
  if choice.kind == "box" and choice.file then
    local ok, i = pcall(love.graphics.newImage, "assets/box/" .. choice.file)
    if ok then img = i end
  elseif choice.kind == "custom" and choice.file then
    local ok, i = pcall(love.graphics.newImage, choice.file)
    if ok then img = i end
  end
  if img then img:setFilter("linear", "linear") end
  images[game.id] = img
end

local function cartOf(gameId)
  local cartId = Config.data.cart[gameId]
  if not cartId then return nil, nil end
  for _, c in ipairs(R.listCarts(gameId)) do
    if c.id == cartId then return cartId, c.title end
  end
  Config.data.cart[gameId] = nil
  Config.save()
  return nil, nil
end

function M.refreshGame(gameId)
  local game = Catalog.byId[gameId]
  if not game or game.spinoff or not R.root then return end
  local cartId, cartTitle = cartOf(gameId)
  local info = R.listSlots(gameId, cartId)
  local lines = {}
  if cartTitle then lines[#lines + 1] = { cartTitle, UI.colors.warn } end
  local active
  for _, s in ipairs(info.slots or {}) do if s.active then active = s end end
  if info.needsRecomp then
    lines[#lines + 1] = { "Save not in the list yet", UI.colors.white }
  elseif active then
    lines[#lines + 1] = { R.slotTitle(active), UI.colors.white }
    lines[#lines + 1] = { R.slotDetail(active), UI.colors.dim }
  else
    lines[#lines + 1] = { "No save yet", UI.colors.dim }
  end
  saveInfo[gameId] = { lines = lines }
end

function M.refreshMods()
  mods = R.root and R.listMods() or {}
  modOpts = R.root and (R.readOptions() or {}) or {}
  modOrder = {}
  for i, id in ipairs(R.loadOrder(modOpts, mods)) do modOrder[id] = i end
end

function M.refreshAll()
  for _, tab in ipairs(Catalog.tabs) do
    for _, g in ipairs(tab.games or {}) do M.refreshGame(g.id) end
  end
  M.refreshMods()
end

function M.init(app)
  App = app
  for _, tab in ipairs(Catalog.tabs) do
    for _, g in ipairs(tab.games or {}) do loadImage(g) end
  end
  M.refreshAll()
  M.focus = "card_" .. Catalog.tabs[1].games[1].id
end

local function needFolder()
  if R.root then return false end
  App.askFolder()
  return true
end

local function recompFallback(title, msg, gameId)
  App.message(title, msg .. "\n\nGen1 Recomp's own launcher can do this instead.", {
    { label = "Open Gen1 Recomp", onPress = function()
      if gameId then R.openLauncherOn(gameId) else R.launch(nil) end
    end },
    { label = "Back" },
  })
end

---------------------------------------------------------------------------
-- Launching
---------------------------------------------------------------------------
local function launchGame(game)
  if game.spinoff then
    App.toast(game.name .. " isn't playable in Gen1 Recomp yet.")
    return
  end
  if needFolder() then return end
  local ok, err = R.launch(game.id, (cartOf(game.id)))
  if ok then App.toast("Starting " .. game.name .. "...")
  else App.message("Couldn't start the game", tostring(err)) end
end

---------------------------------------------------------------------------
-- Custom Art
---------------------------------------------------------------------------
function M.setCustomArt(game, path)
  local bytes = FS.read(path)
  if not bytes then App.message("Couldn't read that picture", path) return end
  local ext = FS.ext(path) or "png"
  local okData, fd = pcall(love.filesystem.newFileData, bytes, "art." .. ext)
  local okImg = okData and pcall(love.image.newImageData, fd)
  if not okImg then App.message("That picture can't be used", "LOVE couldn't open " .. FS.basename(path)) return end
  love.filesystem.createDirectory("art")
  for _, e in ipairs({ "png", "jpg", "jpeg", "bmp", "tga" }) do
    if e ~= ext then love.filesystem.remove("art/" .. game.id .. "." .. e) end
  end
  local file = "art/" .. game.id .. "." .. ext
  love.filesystem.write(file, bytes)
  Config.data.art[game.id] = { kind = "custom", file = file }
  Config.data.lastArtDir = FS.parent(path)
  Config.save()
  loadImage(game)
  App.toast("Picture set for " .. game.name)
end

local function chooseArt(game)
  local current = artFor(game)
  local rows = {}
  for _, b in ipairs(game.boxes) do
    rows[#rows + 1] = {
      label = b[1] .. " box art",
      marker = (current.kind == "box" and current.file == b[2]) and "IN USE" or nil,
      onPress = function()
        Config.data.art[game.id] = { kind = "box", file = b[2] }
        Config.save()
        loadImage(game)
        App.pop()
      end,
    }
  end
  rows[#rows + 1] = {
    label = "Choose a picture...", detail = "PNG, JPG, BMP or TGA from your computer",
    marker = current.kind == "custom" and "IN USE" or nil,
    onPress = function()
      App.pop()
      App.push(O.fileBrowser({
        title = "Picture for " .. game.name,
        exts = { png = true, jpg = true, jpeg = true, bmp = true, tga = true },
        start = Config.data.lastArtDir,
        onPick = function(path) M.setCustomArt(game, path) end,
      }))
    end,
  }
  rows[#rows + 1] = {
    label = "No picture", detail = "Show the game's name instead",
    marker = current.kind == "none" and "IN USE" or nil,
    onPress = function()
      Config.data.art[game.id] = { kind = "none" }
      Config.save()
      loadImage(game)
      App.pop()
    end,
  }
  App.push(O.list("Custom Art - " .. game.name, rows))
end

---------------------------------------------------------------------------
-- Save Manager (Gen1 Recomp's SAVE card as a pop-up)
---------------------------------------------------------------------------
local openSaveManager

function M.importSave(game, path)
  if cartOf(game.id) then
    App.message("Import", "Saves are imported into the original game. Pick \"None\" in Custom Cart first.")
    return
  end
  local ok, msg, fallback = R.importSave(game.id, path)
  M.refreshGame(game.id)
  if ok then App.toast(msg) openSaveManager(game)
  elseif fallback then recompFallback("Import", msg, game.id)
  else App.message("Import didn't work", msg) end
end

local function pickImport(game)
  App.push(O.fileBrowser({
    title = "Import a save for " .. game.name,
    exts = { sav = true, srm = true, lua = true, sa1 = true, dsv = true },
    start = Config.data.lastSaveDir,
    hint = "A .sav from a cartridge or emulator, or a save exported from Gen1 Recomp.",
    onPick = function(path)
      Config.data.lastSaveDir = FS.parent(path)
      Config.save()
      M.importSave(game, path)
    end,
  }))
end

local function otherSaves(game, cartId, info)
  local rows = {}
  for _, s in ipairs(info.slots) do
    rows[#rows + 1] = {
      label = R.slotTitle(s), detail = R.slotDetail(s),
      marker = s.active and "LOADED" or nil,
      onPress = function()
        local ok, err = R.setActiveSlot(game.id, cartId, s.id)
        App.pop()
        if not ok then App.message("Couldn't change save", tostring(err)) return end
        M.refreshGame(game.id)
        openSaveManager(game)
      end,
    }
  end
  App.push(O.list("Other saves - " .. game.name, rows, { empty = "No saves yet." }))
end

openSaveManager = function(game)
  if needFolder() then return end
  -- one Save Manager at a time: replace an open one
  local cartId, cartTitle = cartOf(game.id)
  local info = R.listSlots(game.id, cartId)   -- read once; actions reopen the panel
  App.push(O.panel(function()
    local active
    for _, s in ipairs(info.slots or {}) do if s.active then active = s end end
    local title = "SAVE - " .. game.name .. (cartTitle and (" (" .. cartTitle .. ")") or "")
    if info.needsRecomp then
      return { title = title, width = 1150, blocks = {
        { kind = "text", text = info.needsRecomp },
        { kind = "buttons", cols = 2, buttons = {
          { label = "Open in Gen1 Recomp", style = "blue", onPress = function() R.openLauncherOn(game.id) end },
          { label = "Close" } } },
      } }
    end
    local noSave = not (active and active.exists)
    local s = active and active.summary or {}
    return { title = title, width = 1150, blocks = {
      { kind = "buttons", cols = 2, height = 66, buttons = {
        { id = "sm_import", label = "Import", disabled = cartId ~= nil,
          whyDisabled = "Saves are imported into the original game.",
          onPress = function() pickImport(game) end },
        { id = "sm_other", label = ("Other saves (%d)"):format(#(info.slots or {})),
          onPress = function() otherSaves(game, cartId, info) end },
      } },
      { kind = "save", title = active and R.slotTitle(active) or "No save yet",
        badge = (active and active.exists) and "LOADED" or nil,
        stats = { { tostring(s.badges or 0), "badges" }, { s.time or "0:00", "played" },
                  { tostring(s.dex or 0), "caught" } } },
      { kind = "buttons", cols = 2, height = 66, buttons = {
        { id = "sm_export", label = "Export", disabled = noSave or cartId ~= nil,
          whyDisabled = cartId and "Cart saves can't be exported." or "No save to export yet.",
          onPress = function()
            local ok, msg, fallback = R.exportSave(game.id)
            if ok then
              App.message("Export", "Saved to:\n" .. msg, {
                { label = "Open folder", onPress = function() FS.openFolder(FS.parent(FS.norm(msg)) or R.root) end },
                { label = "OK" } })
            elseif fallback then recompFallback("Export", msg, game.id)
            else App.message("Export didn't work", msg) end
          end },
        { id = "sm_dup", label = "Duplicate", disabled = noSave, whyDisabled = "No save to copy yet.",
          onPress = function()
            local ok, msg, fallback = R.duplicateSlot(game.id, cartId, active.id)
            M.refreshGame(game.id)
            if ok then App.toast("Save copied") openSaveManager(game)
            elseif fallback then recompFallback("Duplicate", msg, game.id)
            else App.message("Duplicate didn't work", msg) end
          end },
        { id = "sm_rename", label = "Rename", disabled = not active, whyDisabled = "No save to rename yet.",
          onPress = function()
            App.push(O.textInput("Rename " .. R.slotTitle(active), active.label or "", function(text)
              local ok, err = R.renameSlot(game.id, cartId, active.id, text)
              if not ok then App.message("Couldn't rename", tostring(err)) return end
              M.refreshGame(game.id)
              openSaveManager(game)
            end))
          end },
        { id = "sm_edit", label = "Edit save", disabled = noSave,
          whyDisabled = "No save to edit yet.",
          onPress = function()
            local ok, err = R.editSave(game.id, cartId, active.id)
            if ok then App.toast("Opening the save editor on " .. R.slotTitle(active) .. "...")
            else App.message("Edit save", tostring(err)) end
          end },
        { id = "sm_delete", label = "Delete", style = "danger", disabled = not active,
          whyDisabled = "No save to delete.",
          onPress = function()
            App.message("Delete save?", ("Delete \"%s\" for good? This can't be undone."):format(R.slotTitle(active)), {
              { label = "Delete", onPress = function()
                local ok, msg, fallback = R.deleteSlot(game.id, cartId, active.id)
                M.refreshGame(game.id)
                if ok then App.toast("Save deleted") openSaveManager(game)
                elseif fallback then recompFallback("Delete", msg, game.id)
                else App.message("Delete didn't work", msg) end
              end },
              { label = "Keep it" } })
          end },
      } },
      { kind = "buttons", cols = 1, height = 72, buttons = {
        { id = "sm_new", label = "+ New save slot", style = "green", onPress = function()
          local ok, err = R.createSlot(game.id, cartId)
          M.refreshGame(game.id)
          if not ok then App.message("Couldn't make a new save", tostring(err)) return end
          App.toast("New save ready. Start " .. game.name .. " to begin it.")
          openSaveManager(game)
        end },
        { id = "sm_close", label = "Close" },
      } },
    } }
  end))
end

---------------------------------------------------------------------------
-- Custom Cart
---------------------------------------------------------------------------
local function chooseCart(game)
  if needFolder() then return end
  local carts = R.listCarts(game.id)
  local current = cartOf(game.id)
  local rows = { {
    label = "None", detail = "Play the original game",
    marker = not current and "IN USE" or nil,
    onPress = function()
      Config.data.cart[game.id] = nil
      Config.save()
      M.refreshGame(game.id)
      App.pop()
    end,
  } }
  for _, c in ipairs(carts) do
    local detail = {}
    if c.author then detail[#detail + 1] = "by " .. tostring(c.author) end
    if c.version then detail[#detail + 1] = "v" .. tostring(c.version) end
    if not c.present then detail[#detail + 1] = "cart file missing" end
    rows[#rows + 1] = {
      label = c.title, detail = table.concat(detail, " - "), disabled = not c.present,
      marker = current == c.id and "IN USE" or nil,
      onPress = function()
        Config.data.cart[game.id] = c.id
        Config.save()
        M.refreshGame(game.id)
        App.pop()
        App.toast(game.name .. " will start " .. c.title)
      end,
    }
  end
  App.push(O.list("Custom Cart - " .. game.name, rows, {
    subtitle = #carts == 0 and "No carts for this game yet. Make one with \"Save as cart\" in Gen1 Recomp's Mods tab." or nil,
  }))
end

---------------------------------------------------------------------------
-- ID Sync
---------------------------------------------------------------------------
local function idSync(game)
  if needFolder() then return end
  local cartId = cartOf(game.id)
  local info = R.listSlots(game.id, cartId)
  local active
  for _, s in ipairs(info.slots or {}) do if s.active and s.exists then active = s end end
  if not active then
    App.message("ID Sync", info.needsRecomp or "Pick your save first. Every save will use its trainer name and ID.")
    return
  end
  local profile, why, fallback = R.idSyncProfile(game.id, cartId, active.id)
  if not profile then
    if fallback then recompFallback("ID Sync", tostring(why), game.id)
    else App.message("ID Sync", tostring(why)) end
    return
  end
  App.push(O.panel(function()
    return { title = "ID Sync", width = 1100, blocks = {
      { kind = "text", text = ("Use %s - ID %05d across your saves?"):format(tostring(profile.name), tonumber(profile.id) or 0) },
      { kind = "text", text = "Your Pokemon get the same OT name and ID, including the secret ID in Gen 3. Party, PC, daycare and launcher Box are included." },
      { kind = "text", text = "Shiny stays shiny. Personality only changes if needed; a Spinda's spots can change with it." },
      { kind = "gap", h = 10 },
      { kind = "buttons", cols = 2, buttons = {
        { id = "ids_go", label = "Sync", style = "green", onPress = function()
          local job, err = R.idSyncJob(game.id, cartId, active.id)
          if not job then recompFallback("ID Sync", tostring(err), game.id) return end
          App.runJob("Syncing trainer identity", job, function(ok, j, stepErr)
            M.refreshAll()
            if not ok or j.error then
              App.message("ID Sync failed", tostring(ok and j.error or stepErr))
              return
            end
            local lines = { ("%s - ID %05d is now on your saves. %d save(s) updated."):format(
              tostring(j.target and j.target.name or profile.name), tonumber(j.newId) or 0, j.written or 0) }
            if j.boxUpdated then lines[#lines + 1] = "Launcher Box updated too." end
            local rep = j.report or {}
            if (rep.personalities or 0) > 0 then
              lines[#lines + 1] = ("Shiny status kept. %d personality value(s) adjusted."):format(rep.personalities)
            end
            if (rep.spinda or 0) > 0 then lines[#lines + 1] = ("%d Spinda spot pattern(s) changed."):format(rep.spinda) end
            if (rep.unknown or 0) > 0 then
              lines[#lines + 1] = ("%d record(s) had no OT name, so their ownership couldn't be checked."):format(rep.unknown)
            end
            App.message("ID Sync", table.concat(lines, "\n"))
          end)
        end },
        { id = "ids_cancel", label = "Cancel" },
      } },
    } }
  end))
end

---------------------------------------------------------------------------
-- Menu drop-down
---------------------------------------------------------------------------
local MENU = {
  { key = "art",   label = "Custom Art",   run = chooseArt },
  { key = "saves", label = "Save Manager", run = function(g) openSaveManager(g) end },
  { key = "cart",  label = "Custom Cart",  run = chooseCart },
  { key = "idsync", label = "ID Sync",     run = idSync },
}

---------------------------------------------------------------------------
-- Bottom bar: controller swap, Settings, the green buttons, Save Sync, EXIT
---------------------------------------------------------------------------
local release

local function parseRelease(body)
  local doc = S.decodeJson(body)
  if type(doc) ~= "table" or not doc.tag_name then
    local msg = type(doc) == "table" and doc.message or nil
    return nil, msg and ("GitHub said: " .. msg) or "GitHub's answer couldn't be read."
  end
  local version = tostring(doc.tag_name):gsub("^v", "")
  local payload = "gen1recomp-" .. version .. ".love"
  local rel = { version = version, notes = doc.body or "", payload = payload }
  for _, a in ipairs(doc.assets or {}) do
    if a.name == payload then rel.payloadUrl = a.browser_download_url end
    if a.name == "sha256sums.txt" then rel.sumsUrl = a.browser_download_url end
  end
  return rel
end

local RELEASE_API = "https://api.github.com/repos/bryanthaboi/gen1recomp/releases/latest"

local function showNotes(rel)
  App.push(O.textViewer("Patch notes - v" .. rel.version, rel.notes ~= "" and rel.notes or "No notes for this release."))
end

local function checkUpdates(mode)
  if needFolder() then return end
  if mode == "notes" and release then showNotes(release) return end
  App.toast(mode == "notes" and "Getting patch notes..." or "Checking for updates...")
  App.request({ cmd = "fetch", url = RELEASE_API }, function(res)
    if not res.ok then App.message("Updates", res.message) return end
    local rel, err = parseRelease(res.body)
    if not rel then App.message("Updates", err) return end
    release = rel
    if mode == "notes" then showNotes(rel) return end
    local have = R.installedVersion()
    if have and R.compareVersions(have, rel.version) >= 0 then
      App.message("Updates", ("Gen1 Recomp is up to date (v%s)."):format(have))
      return
    end
    if not rel.payloadUrl then
      App.message("Updates", ("v%s is out, but it has no update file the frontend can install. "
        .. "Gen1 Recomp's own launcher can update it."):format(rel.version))
      return
    end
    local line = have and ("You have v%s. Download v%s?"):format(have, rel.version)
      or ("v%s is the newest release. Gen1 Recomp hasn't downloaded any updates yet, "
        .. "so it's using the version that came with the program. Download v%s?"):format(rel.version, rel.version)
    App.message("Update available", line, {
      { label = "Download", fill = UI.colors.green, onPress = function()
        local dir = R.updatesDir()
        if not dir or not FS.mkdirp(dir) then
          App.message("Updates", "Couldn't find or make Gen1 Recomp's updates folder.")
          return
        end
        App.busy("Downloading v" .. rel.version .. "...")
        App.request({ cmd = "download", url = rel.payloadUrl, sumsUrl = rel.sumsUrl, name = rel.payload,
          path = dir .. "/" .. rel.payload }, function(r)
          App.busy(nil)
          if r.ok then App.message("Updated", "The update is downloaded. Gen1 Recomp will use it the next time it starts.")
          else App.message("Update failed", r.message) end
        end)
      end },
      { label = "Patch notes", onPress = function() showNotes(rel) end },
      { label = "Not now" },
    })
  end)
end

local function onOff(v) return v and "On" or "Off" end

-- options.lua as last read; dropped after every change so it's re-read once
local optsCache
local function opts() optsCache = optsCache or R.readOptions() or {} return optsCache end
local function vol(v) v = tonumber(v) or 7 return v == 0 and "Off" or tostring(v) end

local function setOpt(fn)
  optsCache = nil
  local ok, err = R.updateOptions(fn)
  if not ok then App.toast("Couldn't save: " .. tostring(err)) end
end

local function troubleshooting()
  optsCache = nil
  App.push(O.settings(function()
    local opts = opts()
    return { title = "Troubleshooting", rows = {
      { label = "Safe mode", note = "Temporarily disable every mod while you reproduce a bug.",
        value = function() return onOff(opts.safeMode == true) end,
        step = function() setOpt(function(o) o.safeMode = not (o.safeMode == true) end) end },
      { label = "Gen1 Recomp folder", note = R.dir,
        action = { label = "Open", onPress = function() FS.openFolder(R.dir) end } },
      { label = "Bug report", note = "Gen1 Recomp's bug report form lives in its own launcher.",
        action = { label = "Open", onPress = function() R.launch(nil) end } },
    }, footer = { { label = "Done", style = "blue", onPress = function() App.pop() end } } }
  end))
end

-- The frontend's own window row (Video Mode switches this window).
local function videoRow()
  return { label = "Video Mode", choices = { { value = "windowed", label = "Windowed" },
      { value = "fullscreen", label = "Fullscreen" } },
    selected = function() return love.window.getFullscreen() and "fullscreen" or "windowed" end,
    select = function(v) App.setFullscreen(v == "fullscreen") end }
end

-- Fallback rows when Gen1 Recomp's own Settings can't be loaded.
local function basicRows(opts)
  return {
    { heading = "Launcher Options", note = "Applies immediately" },
    videoRow(),
    { label = "Reduce Motion", value = function() return onOff(opts.reduceMotion == true) end,
      step = function() setOpt(function(o) o.reduceMotion = not (o.reduceMotion == true) end) end },
    { label = "Splash Video", value = function() return onOff(opts.splashVideo ~= false) end,
      step = function() setOpt(function(o) o.splashVideo = o.splashVideo == false end) end },
    { label = "Theme Video BG", value = function() return onOff(opts.themeVideoBg ~= false) end,
      step = function() setOpt(function(o) o.themeVideoBg = o.themeVideoBg == false end) end },
    { label = "Splash Sound", value = function() return onOff(opts.splashMute ~= true) end,
      step = function() setOpt(function(o) o.splashMute = not (o.splashMute == true) end) end },
    { label = "Showcase Music", value = function() return vol(opts.boxMusicVol) end,
      step = function(d) setOpt(function(o)
        o.boxMusicVol = math.max(0, math.min(7, (tonumber(o.boxMusicVol) or 7) + d)) end) end },
    { label = "Showcase Cry", value = function() return vol(opts.boxCryVol) end,
      step = function(d) setOpt(function(o)
        o.boxCryVol = math.max(0, math.min(7, (tonumber(o.boxCryVol) or 7) + d)) end) end },
    { label = "Union Room",
      note = "Adds a Union Room upstairs in Gen 1 and Gen 2 Pokemon Centers. OFF restores the original Centers. Gen 3 Union Rooms always work.",
      value = function() return onOff(opts.unionRoom ~= false) end,
      step = function() setOpt(function(o) o.unionRoom = o.unionRoom == false end) end },
    { label = "Auto Re-import", value = function() return onOff(opts.autoReimport == true) end,
      step = function() setOpt(function(o) o.autoReimport = not (o.autoReimport == true) end) end },
  }
end

-- Gen1 Recomp's gear menu, row for row: its Launcher Options, the Game
-- Options for Gen 1 or Gen 2 games, and every mod's options.
local SETTINGS_FOR = { { "red", "Red, Blue and Yellow" },
  { "gold", "Gold, Silver and Crystal" },
  { "firered", "FireRed, LeafGreen, Ruby, Sapphire and Emerald" } }
local SETTINGS_SHORT = { "Gen 1", "Gen 2", "Gen 3" }

local function recompRows(model, pickIndex, setPick)
  local rows = {}
  local function save()
    local ok, res = pcall(model.save)
    if not ok or res == false then App.toast(model.saveError or "Settings could not be saved.") end
  end
  local safe = type(model.opts) == "table" and model.opts.safeMode == true
  for si, section in ipairs(model.sections or {}) do
    rows[#rows + 1] = { heading = section.title, note = si == 1 and "Applies immediately" or nil }
    if si == 1 then
      -- right after Launcher Options' heading: which games' options show below
      rows[#rows + 1] = { label = "Game Options for", note = SETTINGS_FOR[pickIndex][2],
        value = function() return SETTINGS_SHORT[pickIndex] end,
        step = function(d) setPick(((pickIndex - 1 + d) % #SETTINGS_FOR) + 1) end }
    end
    for _, r in ipairs(section.rows or {}) do
      local label = tostring(r.label or "")
      local blocked = r.safeModeBlocked and safe
      if label == "Video Mode" then
        rows[#rows + 1] = videoRow()
      elseif r.editText then
        rows[#rows + 1] = { label = label, note = r.note, value = function() return tostring(r.value()) end,
          action = { label = "Edit", onPress = function()
            App.push(O.textInput(label, tostring(r.value() or ""), function(text)
              pcall(r.setText, text)
              save()
            end, r.editText.maxLen))
          end } }
      elseif r.choices then
        rows[#rows + 1] = { label = label, note = r.note, choices = r.choices,
          selected = function() local ok, v = pcall(r.selected) return ok and v or nil end,
          select = function(v) if pcall(r.select, v) then save() end end }
      elseif r.action then
        local actionLabel = type(r.actionLabel) == "function" and r.actionLabel() or r.actionLabel or "Run"
        rows[#rows + 1] = { label = label, note = r.note, disabled = blocked,
          action = { label = actionLabel, style = r.danger and "danger" or nil, onPress = function()
            if blocked then App.toast("Turn off Safe mode first.") return end
            local function run()
              local ok, res = pcall(r.action)
              if ok and res ~= false then
                save()
                if r.doneText then App.toast(r.doneText) end
              elseif not ok then App.toast(tostring(res)) end
            end
            if r.confirm then
              App.message(r.confirm.title or label, table.concat(r.confirm.lines or {}, "\n"), {
                { label = "Yes", onPress = run }, { label = "No" } })
            else run() end
          end } }
      elseif r.value then
        rows[#rows + 1] = { label = label, note = r.note, disabled = blocked,
          value = function() local ok, v = pcall(r.value) return ok and tostring(v) or "?" end,
          step = r.step and function(d)
            if blocked then App.toast("Turn off Safe mode first.") return end
            local ok, changed = pcall(r.step, d)
            if ok and changed then save() elseif not ok then App.toast(tostring(changed)) end
          end or nil }
      end
    end
  end
  return rows
end

function M.openSettings()
  if needFolder() then return end
  optsCache = nil
  local pick = 1
  local model, why
  local hooks = {
    openExtras = function() R.openLauncherTab("importers") end,
  }
  local function load()
    model, why = R.settingsModel(SETTINGS_FOR[pick][1], hooks)
  end
  load()
  App.push(O.settings(function()
    local rows
    if model then
      rows = recompRows(model, pick, function(i) pick = i load() end)
    else
      rows = basicRows(opts())
    end
    return {
      title = "Settings",
      subtitle = model and "Saved automatically" or "Saved automatically (basic list: Gen1 Recomp's full Settings couldn't be loaded)",
      rows = rows,
      footer = {
        { label = "Troubleshooting", onPress = troubleshooting },
        { label = "Done", style = "blue", onPress = function() App.pop() end },
      },
    }
  end))
end

local function saveSync()
  if needFolder() then return end
  local status, linked = R.syncStatus()
  App.push(O.panel(function()
    local function handOff()
      App.message("Save Sync", "Save Sync accounts are set up in Gen1 Recomp's launcher. Open it now?", {
        { label = "Open Gen1 Recomp", onPress = function() R.launch(nil) end }, { label = "Back" } })
    end
    local buttons = linked and {
      { label = "Manage in Gen1 Recomp", style = "blue", onPress = handOff },
      { label = "Close" },
    } or {
      { label = "Create sync account", style = "green", onPress = handOff },
      { label = "Link this device", style = "blue", onPress = handOff },
      { label = "Close" },
    }
    return { title = "SAVE SYNC", width = 1000, blocks = {
      { kind = "text", text = "Cloud sync keeps your game saves, Box collection and mod list on our server so another device can pick them up. Keep your own backups too." },
      { kind = "text", text = status, color = linked and UI.colors.ok or UI.colors.dim },
      { kind = "buttons", cols = 1, buttons = buttons },
    } }
  end))
end

function M.confirmExit()
  App.message("Quit", "Close the frontend?", {
    { label = "Quit", onPress = function() love.event.quit() end },
    { label = "Stay" },
  })
end

local function openTab(tab, name)
  if needFolder() then return end
  local ok, err = R.openLauncherTab(tab)
  if ok then App.toast("Opening " .. name .. " in Gen1 Recomp...")
  else App.message(name, tostring(err)) end
end

local function bottomBar(items)
  local y, h = 990, 80
  local greens = {
    { "bb_folder", "Open Game Folder", 8, 296, function()
      if needFolder() then return end
      local ok, err = FS.openFolder(R.dir)
      if ok == false then App.message("Open Game Folder", tostring(err)) end
    end },
    { "bb_updates", "Check for Updates", 314, 300, function() checkUpdates("check") end },
    { "bb_notes", "Patch Notes", 624, 266, function() checkUpdates("notes") end },
  }
  for _, g in ipairs(greens) do
    items[#items + 1] = { id = g[1], label = g[2], x = g[3], y = y, w = g[4], h = h,
      fill = UI.colors.green, edge = UI.colors.greenEdge, font = UI.pixel(33), onPress = g[5] }
  end
  items[#items + 1] = { id = "bb_swap", kind = "swap", x = 900, y = y, w = 196, h = h,
    onPress = function()
      Config.set("swapAB", not Config.data.swapAB)
      App.toast(Config.data.swapAB and "Gamepad: B confirms, A cancels" or "Gamepad: A confirms, B cancels")
    end }
  local icons = {
    { "bb_settings", "Settings", "gear", function() M.openSettings() end },
    { "bb_sync", "Save Sync", "sync", function() saveSync() end },
    { "bb_box", "BOX", "box", function() openTab("box", "Box") end },
    { "bb_online", "Online", "globe", function() openTab("online", "Online") end },
    { "bb_skins", "SKINS", "brush", function() openTab("skins", "Skins") end },
  }
  local ix, iw, gap = 1104, 130, 7
  for i, ic in ipairs(icons) do
    items[#items + 1] = { id = ic[1], label = ic[2], icon = ic[3], kind = "plain",
      x = ix + (i - 1) * (iw + gap), y = y, w = iw, h = h, onPress = ic[4] }
  end
  items[#items + 1] = { id = "bb_exit", label = "EXIT", kind = "plain", x = 1793, y = y, w = 119, h = h,
    font = UI.pixel(44), onPress = M.confirmExit }
end

-- Small line icons for the bottom bar.
local function drawIcon(kind, cx, cy)
  love.graphics.setLineWidth(3)
  UI.setColor(UI.colors.white)
  if kind == "gear" then
    love.graphics.circle("line", cx, cy, 9)
    for i = 0, 7 do
      local a = i * math.pi / 4
      love.graphics.line(cx + math.cos(a) * 11, cy + math.sin(a) * 11, cx + math.cos(a) * 16, cy + math.sin(a) * 16)
    end
    love.graphics.circle("line", cx, cy, 13)
  elseif kind == "sync" then
    love.graphics.line(cx - 14, cy - 6, cx + 14, cy - 6)
    love.graphics.line(cx + 14, cy - 6, cx + 8, cy - 12)
    love.graphics.line(cx + 14, cy - 6, cx + 8, cy)
    love.graphics.line(cx + 14, cy + 7, cx - 14, cy + 7)
    love.graphics.line(cx - 14, cy + 7, cx - 8, cy + 1)
    love.graphics.line(cx - 14, cy + 7, cx - 8, cy + 13)
  elseif kind == "box" then
    love.graphics.polygon("line", cx, cy - 15, cx + 14, cy - 8, cx, cy - 1, cx - 14, cy - 8)
    love.graphics.line(cx - 14, cy - 8, cx - 14, cy + 9, cx, cy + 16, cx + 14, cy + 9, cx + 14, cy - 8)
    love.graphics.line(cx, cy - 1, cx, cy + 16)
  elseif kind == "globe" then
    love.graphics.circle("line", cx, cy, 15)
    love.graphics.ellipse("line", cx, cy, 6, 15)
    love.graphics.line(cx - 15, cy, cx + 15, cy)
    love.graphics.line(cx - 12, cy - 8, cx + 12, cy - 8)
    love.graphics.line(cx - 12, cy + 8, cx + 12, cy + 8)
  elseif kind == "brush" then
    love.graphics.line(cx + 12, cy - 15, cx - 2, cy + 1)
    love.graphics.line(cx + 15, cy - 12, cx + 1, cy + 4)
    love.graphics.polygon("line", cx - 2, cy + 1, cx + 1, cy + 4, cx - 6, cy + 16, cx - 15, cy + 12)
  end
end

local function drawPlain(it, focused)
  UI.setColor(UI.colors.bg)
  love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 8, 8)
  love.graphics.setLineWidth(3)
  UI.setColor(UI.colors.white)
  love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 8, 8)
  if it.kind == "swap" then
    local swap = Config.data.swapAB
    local top = swap and "B" or "A"
    local bottom = swap and "A" or "B"
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", it.x + 34, it.y + 21, 17)
    love.graphics.circle("line", it.x + 34, it.y + 59, 17)
    UI.textCentered(top, UI.sans(22), it.x + 17, it.y + 4, 34, 34, UI.colors.white)
    UI.textCentered(bottom, UI.sans(22), it.x + 17, it.y + 42, 34, 34, UI.colors.white)
    local f = UI.pixel(33)
    UI.textCentered("Confirm", f, it.x + 56, it.y + 2, it.w - 56, 38, UI.colors.white)
    UI.textCentered("Cancel", f, it.x + 56, it.y + 40, it.w - 56, 38, UI.colors.white)
  elseif it.icon then
    drawIcon(it.icon, it.x + it.w / 2, it.y + 25)
    UI.textCentered(it.label, UI.pixel(33), it.x, it.y + 40, it.w, 40, UI.colors.white)
  else
    local font = it.font or UI.pixel(22)
    UI.textCentered(it.label, font, it.x, it.y, it.w, it.h, UI.colors.white)
  end
  if focused then UI.focusRing(it, 5) end
end

---------------------------------------------------------------------------
-- Layout: games tabs
---------------------------------------------------------------------------
local function gameLayout(tab, items)
  local games = tab.games
  local n = #games
  local margin, gap = 30, (n > 6) and 26 or 40
  local cardW = math.floor((UI.W - margin * 2 - gap * (n - 1)) / n)
  local cardH = math.min(math.floor(cardW * 1.25), 360)
  local cardY = 160
  local menuY = cardY + cardH + 112
  local x0 = margin + math.floor((UI.W - margin * 2 - (cardW * n + gap * (n - 1))) / 2)
  for i, g in ipairs(games) do
    local x = x0 + (i - 1) * (cardW + gap)
    items[#items + 1] = { id = "card_" .. g.id, kind = "card", game = g,
      x = x, y = cardY, w = cardW, h = cardH, onPress = function() launchGame(g) end }
    items[#items + 1] = { id = "menu_" .. g.id, kind = "menu", game = g, label = "Menu",
      x = x, y = menuY, w = cardW, h = 62,
      onPress = function()
        if M.menuOpen == g.id then
          M.menuOpen = nil
        else
          M.menuOpen = g.id
          App.setFocus("dd_" .. g.id .. "_1")
        end
      end }
    if M.menuOpen == g.id then
      for k, entry in ipairs(MENU) do
        local disabled = g.spinoff and entry.key ~= "art"
        items[#items + 1] = { id = "dd_" .. g.id .. "_" .. k, kind = "dd", game = g, label = entry.label,
          x = x + 4, y = menuY + 62 + 6 + (k - 1) * 66, w = cardW - 8, h = 58, disabled = disabled,
          onPress = function()
            if disabled then App.toast("Not available for spin-offs yet.") return end
            M.menuOpen = nil
            M.focus = "menu_" .. g.id
            entry.run(g)
          end }
      end
    end
  end
end

local function drawCard(it, focused)
  local g = it.game
  UI.setColor(UI.colors.bg)
  love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 12, 12)
  local img = images[g.id]
  if img then
    love.graphics.setScissor(it.x, it.y, it.w, it.h)
    UI.imageContain(img, it.x + 6, it.y + 6, it.w - 12, it.h - 12)
    love.graphics.setScissor()
  else
    UI.textCentered(g.name, UI.pixel(44), it.x, it.y, it.w, it.h, UI.colors.white)
  end
  love.graphics.setLineWidth(focused and 6 or 4)
  UI.setColor(focused and UI.colors.focus or UI.colors.white)
  love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 12, 12)
  love.graphics.setLineWidth(1)
  if focused then UI.focusRing(it, 8) end
  -- the cart and save this card will start, up to three lines
  local info = saveInfo[g.id]
  if info and not g.spinoff then
    for i, line in ipairs(info.lines) do
      local font = i == #info.lines and #info.lines > 1 and UI.sans(22) or UI.sans(27)
      UI.textCentered(line[1], font, it.x - 8, it.y + it.h + 6 + (i - 1) * 33, it.w + 16, 33, line[2])
    end
  elseif g.spinoff then
    UI.textCentered(g.name, UI.sans(27), it.x - 8, it.y + it.h + 6, it.w + 16, 33, UI.colors.white)
  end
end

local function drawMenuButton(it, focused)
  local open = M.menuOpen == it.game.id
  UI.setColor({ 0.52, 0.0, 0.08 })
  love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 8, 8)
  love.graphics.setLineWidth(4)
  UI.setColor(UI.colors.red)
  love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 8, 8)
  UI.textCentered(open and "Menu  -" or "Menu", UI.pixel(44), it.x, it.y, it.w, it.h, UI.colors.white)
  if focused then UI.focusRing(it, 5) end
end

local function drawDropItem(it, focused)
  local a = it.disabled and 0.4 or 1
  UI.setColor(UI.colors.white, a)
  love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 6, 6)
  love.graphics.setLineWidth(4)
  UI.setColor(UI.colors.red, a)
  love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 6, 6)
  UI.textCentered(it.label, UI.pixel(33), it.x, it.y, it.w, it.h, { 0, 0, 0, a })
  if focused then UI.focusRing(it, 4) end
end

---------------------------------------------------------------------------
-- Layout: Mods tab
---------------------------------------------------------------------------
local MOD_X, MOD_Y, MOD_W, MOD_H = 160, 158, 1600, 815
local LIST_Y = MOD_Y + 250
local LIST_H = MOD_Y + MOD_H - LIST_Y - 16
local ROW_H = 220

local function modsShown()
  local out = {}
  for _, m in ipairs(mods) do
    local ok = M.modFilter == "all"
    if not ok then
      for _, g in ipairs(m.games) do if g == M.modFilter then ok = true end end
    end
    if ok then out[#out + 1] = m end
  end
  table.sort(out, function(a, b)
    if M.modSort == "order" then return (modOrder[a.id] or 999) < (modOrder[b.id] or 999) end
    if M.modSort == "category" and (a.category or "") ~= (b.category or "") then
      return tostring(a.category or "~"):lower() < tostring(b.category or "~"):lower()
    end
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return out
end

local function enabledCount(m)
  local n = 0
  for _, g in ipairs(m.games) do if R.modEnabled(modOpts, m, g) then n = n + 1 end end
  return n
end

local function applyMods(changes, what)
  local ok, err = R.setModsEnabled(changes, mods)
  M.refreshMods()
  if not ok then App.message("Mods", "Couldn't save: " .. tostring(err)) return end
  if what then App.toast(what) end
end

local function perGameMenu(m)
  local rows = {}
  for _, g in ipairs(m.games) do
    local on = R.modEnabled(modOpts, m, g)
    rows[#rows + 1] = {
      label = (Catalog.byId[g] and Catalog.byId[g].name) or g, marker = on and "ON" or "OFF",
      markerColor = on and UI.colors.ok or UI.colors.red,
      onPress = function()
        applyMods({ { m, g, not R.modEnabled(modOpts, m, g) } })
        App.pop()
        perGameMenu(m)
      end,
    }
  end
  App.push(O.list(m.name, rows, { subtitle = "Choose which games use this mod" }))
end

function M.importModZip(path, done)
  if needFolder() then return end
  local ok, msg = R.installModZip(path)
  M.refreshMods()
  if done then done(ok, msg) return end
  App.message(ok and "Mod installed" or "Mod not installed", msg)
end

-- Download a mod release .zip from GitHub and install it.
local function installRelease(m, rel)
  local zip
  for _, a in ipairs(rel.assets or {}) do
    if type(a.name) == "string" and a.name:lower():match("%.zip$") then
      if not zip or a.name:lower():find(m.id:lower(), 1, true) == 1 then zip = a end
    end
  end
  if not zip then App.message("Mods", "That release has no .zip to install.") return end
  local tmp = love.filesystem.getSaveDirectory() .. "/download.zip"
  App.busy("Downloading " .. m.name .. " " .. tostring(rel.tag_name) .. "...")
  App.request({ cmd = "download", url = zip.browser_download_url, path = tmp }, function(res)
    App.busy(nil)
    if not res.ok then App.message("Mods", res.message) return end
    M.importModZip(res.path, function(ok, msg)
      os.remove(res.path)
      App.message(ok and "Mod updated" or "Mod not updated", msg)
    end)
  end)
end

local openModDetails

local function modCheckUpdate(m)
  local repo = m.manifest.github
  if type(repo) ~= "string" or repo == "" then
    App.message("Check for updates", "This mod doesn't say where its updates come from.")
    return
  end
  App.toast("Checking " .. m.name .. "...")
  App.request({ cmd = "fetch", url = "https://api.github.com/repos/" .. repo .. "/releases/latest" }, function(res)
    if not res.ok then App.message("Check for updates", res.message) return end
    local rel = S.decodeJson(res.body)
    if type(rel) ~= "table" or not rel.tag_name then
      App.message("Check for updates", "No releases found for " .. repo .. ".")
      return
    end
    local newest = tostring(rel.tag_name):gsub("^[vV]", "")
    if R.compareVersions(m.version, newest) >= 0 then
      App.message("Check for updates", ("%s is up to date (v%s)."):format(m.name, tostring(m.version)))
      return
    end
    App.message("Update available", ("%s v%s is out (you have v%s). Install it?"):format(m.name, newest, tostring(m.version)), {
      { label = "Install", onPress = function() installRelease(m, rel) end },
      { label = "Not now" } })
  end)
end

local function modVersions(m)
  local repo = m.manifest.github
  if type(repo) ~= "string" or repo == "" then
    App.message("Versions", "This mod doesn't say where its releases are.")
    return
  end
  App.toast("Getting versions...")
  App.request({ cmd = "fetch", url = "https://api.github.com/repos/" .. repo .. "/releases?per_page=50" }, function(res)
    if not res.ok then App.message("Versions", res.message) return end
    local list = S.decodeJson(res.body)
    if type(list) ~= "table" or #list == 0 then App.message("Versions", "No releases found.") return end
    local rows = {}
    for _, rel in ipairs(list) do
      local v = tostring(rel.tag_name or "?"):gsub("^[vV]", "")
      rows[#rows + 1] = {
        label = "v" .. v .. (rel.prerelease and "  (pre-release)" or ""),
        detail = tostring(rel.published_at or ""):sub(1, 10),
        marker = R.compareVersions(v, m.version) == 0 and "INSTALLED" or nil,
        onPress = function()
          App.pop()
          App.message("Install v" .. v .. "?", ("Replace %s v%s with v%s?"):format(m.name, tostring(m.version), v), {
            { label = "Install", onPress = function() installRelease(m, rel) end },
            { label = "Back" } })
        end,
      }
    end
    App.push(O.list("Versions - " .. m.name, rows))
  end)
end

local function modDependencies(m)
  local deps = R.modDependencies(m, mods)
  local rows = {}
  for _, d in ipairs(deps) do
    local status
    if d.have then status = "Installed v" .. tostring(d.have)
    else status = d.need == "required" and "Missing - needed" or "Not installed (optional)" end
    rows[#rows + 1] = { label = d.name, detail = status .. (d.range and ("  - wants " .. d.range) or ""),
      marker = d.have and "OK" or (d.need == "required" and "MISSING" or nil),
      markerColor = d.have and UI.colors.ok or UI.colors.red }
  end
  App.push(O.list("Dependencies - " .. m.name, rows, {
    empty = "This mod doesn't need any other mods." }))
end

openModDetails = function(m)
  App.push(O.panel(function()
    local order = R.loadOrder(modOpts, mods)
    local pos
    for i, id in ipairs(order) do if id == m.id then pos = i end end
    local first, last = pos == 1, pos == #order
    local function move(where)
      local ok, err = R.moveMod(m.id, where, mods)
      M.refreshMods()
      if not ok and err ~= "cancelled" then App.toast("Couldn't move: " .. tostring(err)) end
    end
    return { title = m.name, subtitle = "v" .. tostring(m.version) .. "   " .. (m.experimental and "Experimental" or "Ready"),
      width = 900, blocks = {
        { kind = "buttons", cols = 2, buttons = {
          { id = "md_up", label = "Move up", disabled = first, keepOpen = true, onPress = function() move(-1) end },
          { id = "md_down", label = "Move down", disabled = last, keepOpen = true, onPress = function() move(1) end },
          { id = "md_top", label = "Move to top", disabled = first, keepOpen = true, onPress = function() move("top") end },
          { id = "md_bottom", label = "Move to bottom", disabled = last, keepOpen = true, onPress = function() move("bottom") end },
        } },
        { kind = "buttons", cols = 1, buttons = {
          { id = "md_check", label = "Check for updates", keepOpen = true, onPress = function() modCheckUpdate(m) end },
          { id = "md_versions", label = "Versions", style = "blue", keepOpen = true, onPress = function() modVersions(m) end },
          { id = "md_deps", label = "Check dependencies", style = "blue", keepOpen = true, onPress = function() modDependencies(m) end },
          { id = "md_delete", label = "Delete", style = "danger", onPress = function()
            App.message("Delete mod?", ("Delete %s from Gen1 Recomp's mods folder?"):format(m.name), {
              { label = "Delete", onPress = function()
                local ok, err = R.deleteMod(m)
                M.refreshMods()
                if ok then App.toast(m.name .. " deleted") else App.message("Delete", tostring(err)) end
              end },
              { label = "Keep it", onPress = function() openModDetails(m) end } })
          end },
          { id = "md_close", label = "Close" },
        } },
      } }
  end))
end

local function modsLayout(items)
  local px, py = MOD_X + 20, MOD_Y + 16
  items[#items + 1] = { id = "m_installed", label = "Installed", x = px, y = py, w = 240, h = 56,
    fill = UI.colors.white, edge = UI.colors.panelEdge, font = UI.sans(24), onPress = function() end }
  items[#items + 1] = { id = "m_search", label = "Search (later)", x = px + 256, y = py, w = 240, h = 56,
    fill = UI.colors.panel2, edge = UI.colors.panelEdge, font = UI.sans(24), disabled = true,
    textColor = UI.colors.white,
    onPress = function() App.toast("Searching online mods comes in a later build.") end }
  local sortLabel = ({ order = "Load order", name = "Name", category = "Category" })[M.modSort]
  local tools = {
    { "m_sort", "Sort: " .. sortLabel, UI.colors.panel2, function()
      M.modSort = ({ order = "name", name = "category", category = "order" })[M.modSort] end },
    { "m_enable", "Enable all", UI.colors.ok, function()
      local ch = {}
      for _, m in ipairs(modsShown()) do
        for _, g in ipairs(m.games) do
          if M.modFilter == "all" or g == M.modFilter then ch[#ch + 1] = { m, g, true } end
        end
      end
      applyMods(ch, "Mods enabled")
    end },
    { "m_disable", "Disable all", UI.colors.saves, function()
      local ch = {}
      for _, m in ipairs(modsShown()) do
        for _, g in ipairs(m.games) do
          if M.modFilter == "all" or g == M.modFilter then ch[#ch + 1] = { m, g, false } end
        end
      end
      applyMods(ch, "Mods disabled")
    end },
    { "m_import", "Import mod .zip", UI.colors.blue, function()
      if needFolder() then return end
      App.push(O.fileBrowser({ title = "Import a mod .zip", exts = { zip = true },
        start = Config.data.lastModDir,
        onPick = function(path)
          Config.data.lastModDir = FS.parent(path)
          Config.save()
          M.importModZip(path)
        end }))
    end },
  }
  local tx = MOD_X + MOD_W - 20
  for i = #tools, 1, -1 do
    local t = tools[i]
    local w = UI.sans(24):getWidth(t[2]) + 40
    tx = tx - w
    local light = t[3] == UI.colors.panel2 or t[3] == UI.colors.blue
    items[#items + 1] = { id = t[1], label = t[2], x = tx, y = py + 70, w = w, h = 56,
      fill = t[3], edge = UI.colors.panelEdge, font = UI.sans(24), onPress = t[4],
      textColor = light and UI.colors.white or nil }
    tx = tx - 12
  end
  local cx = px + 140
  local chips = { { "all", "All games" } }
  for _, c in ipairs(Catalog.modGames) do chips[#chips + 1] = c end
  for _, c in ipairs(chips) do
    local w = UI.sans(20):getWidth(c[2]) + 28
    items[#items + 1] = { id = "chip_" .. c[1], label = c[2], x = cx, y = py + 150, w = w, h = 46,
      fill = M.modFilter == c[1] and UI.colors.white or UI.colors.panel2,
      edge = UI.colors.panelEdge, font = UI.sans(20), chip = true,
      textColor = M.modFilter ~= c[1] and UI.colors.white or nil,
      onPress = function() M.modFilter = c[1]; M.modScroll = 0 end }
    cx = cx + w + 8
  end
  local shown = modsShown()
  local clip = { MOD_X + 10, LIST_Y, MOD_W - 20, LIST_H }
  local maxScroll = math.max(0, #shown * ROW_H - LIST_H)
  M.modScroll = math.max(0, math.min(maxScroll, M.modScroll))
  for i, m in ipairs(shown) do
    local y = LIST_Y + (i - 1) * ROW_H - M.modScroll
    local n = enabledCount(m)
    local label
    if M.modFilter == "all" then
      label = ("Enabled for: %d game%s"):format(n, n == 1 and "" or "s")
    else
      label = ("Enabled for %s: %s"):format(
        (Catalog.byId[M.modFilter] and Catalog.byId[M.modFilter].name) or M.modFilter,
        R.modEnabled(modOpts, m, M.modFilter) and "ON" or "OFF")
    end
    items[#items + 1] = { id = "mod_" .. m.id .. "_en", modRow = m, rowIndex = i, label = label,
      x = MOD_X + 40, y = y + 112, w = MOD_W - 80, h = 48, clip = clip, font = UI.sans(24), alignLeft = true,
      onPress = function()
        if M.modFilter == "all" then perGameMenu(m)
        else applyMods({ { m, M.modFilter, not R.modEnabled(modOpts, m, M.modFilter) } }) end
      end }
    items[#items + 1] = { id = "mod_" .. m.id .. "_det", modRow = m, rowIndex = i, label = "Details",
      x = MOD_X + 40, y = y + 166, w = MOD_W - 80, h = 44, clip = clip, font = UI.sans(22),
      onPress = function() openModDetails(m) end }
  end
end

local function drawModsPanel(items, focusId)
  UI.panel(MOD_X, MOD_Y, MOD_W, MOD_H)
  UI.textClip("Or drop a mod .zip onto the window.", UI.sans(22), MOD_X + 20, MOD_Y + 92, 600, UI.colors.dim)
  UI.textClip("Show for:", UI.sans(22), MOD_X + 20, MOD_Y + 176, 140, UI.colors.dim)
  local profile = modOpts.activeProfile
  UI.textClip("Profile: " .. (type(profile) == "string" and profile or "none"), UI.sans(20),
    MOD_X + MOD_W - 320, MOD_Y + 30, 300, UI.colors.dim)
  if not R.root then
    UI.textCentered("Pick your Gen1 Recomp folder to see your mods.", UI.sans(28), MOD_X, LIST_Y, MOD_W, 80, UI.colors.dim)
  elseif #modsShown() == 0 then
    UI.textCentered("No mods installed for this game.", UI.sans(28), MOD_X, LIST_Y, MOD_W, 80, UI.colors.dim)
  end
  love.graphics.setScissor(MOD_X + 10, LIST_Y, MOD_W - 20, LIST_H)
  local drawn = {}
  for _, it in ipairs(items) do
    local m = it.modRow
    if m and not drawn[m] then
      drawn[m] = true
      local y = it.y - 112
      UI.setColor(UI.colors.panel, 1)
      love.graphics.rectangle("fill", MOD_X + 24, y, MOD_W - 48, ROW_H - 12, 10, 10)
      love.graphics.setLineWidth(2)
      UI.setColor(UI.colors.panelEdge)
      love.graphics.rectangle("line", MOD_X + 24, y, MOD_W - 48, ROW_H - 12, 10, 10)
      UI.textClip(m.name, UI.sans(30), MOD_X + 44, y + 10, MOD_W - 100, UI.colors.white)
      local cat = (m.category and tostring(m.category):upper() or "MOD")
      local gens = type(m.gameClaim) == "table" and table.concat(m.gameClaim, "+"):upper() or "ALL GAMES"
      UI.textClip(cat .. "  /  " .. gens, UI.sans(18), MOD_X + 44, y + 48, 600, UI.colors.dim)
      UI.textClip("v" .. tostring(m.version) .. (m.experimental and "   Experimental" or "   Ready"),
        UI.sans(22), MOD_X + 44, y + 70, 400, UI.colors.ok)
      UI.textClip(m.description, UI.sans(20), MOD_X + 400, y + 72, MOD_W - 470, UI.colors.white)
    end
  end
  for _, it in ipairs(items) do
    if it.modRow then
      local focused = it.id == focusId
      UI.setColor(focused and UI.colors.panelEdge or UI.colors.panel2)
      love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 8, 8)
      love.graphics.setLineWidth(focused and 4 or 2)
      UI.setColor(focused and UI.colors.focus or UI.colors.panelEdge)
      love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 8, 8)
      if it.alignLeft then
        UI.textClip(it.label .. "   >", it.font, it.x + 20, it.y + (it.h - it.font:getHeight()) / 2, it.w - 40, UI.colors.white)
      else
        UI.textCentered(it.label, it.font, it.x, it.y, it.w, it.h, UI.colors.white)
      end
    end
  end
  love.graphics.setScissor()
end

---------------------------------------------------------------------------
-- Screen interface
---------------------------------------------------------------------------
function M:build()
  local items = {}
  local tabW = 340
  local tabGap = math.floor((UI.W - 40 - tabW * 5) / 4)
  for i, tab in ipairs(Catalog.tabs) do
    items[#items + 1] = { id = "tab" .. i, kind = "tab", tabIndex = i, label = tab.label,
      x = 20 + (i - 1) * (tabW + tabGap), y = 66, w = tabW, h = 72,
      onPress = function()
        if tab.id == "launch" then
          if needFolder() then return end
          local ok, err = R.launch(nil)
          if ok then App.toast("Starting Gen1 Recomp...") else App.message("Couldn't start Gen1 Recomp", tostring(err)) end
        else
          M.activeTab = i
          M.menuOpen = nil
        end
      end }
  end
  items[#items + 1] = { id = "fs_toggle", kind = "fsicon", x = 1846, y = 4, w = 64, h = 56,
    onPress = function() App.toggleFullscreen() end }
  local tab = Catalog.tabs[M.activeTab]
  if tab.games then gameLayout(tab, items)
  elseif tab.id == "mods" then modsLayout(items) end
  bottomBar(items)
  return items
end

function M:defaultFocus() return "tab" .. M.activeTab end

function M:onFocus(item, source)
  if source ~= "mouse" and item.kind == "tab" and Catalog.tabs[item.tabIndex].id ~= "launch" then
    if M.activeTab ~= item.tabIndex then M.menuOpen = nil end
    M.activeTab = item.tabIndex
  end
  -- moving away from an open Menu closes it
  if M.menuOpen and source ~= "mouse" then
    local inMenu = item.game and item.game.id == M.menuOpen and (item.kind == "dd" or item.kind == "menu")
    if not inMenu then M.menuOpen = nil end
  end
  if item.modRow and item.rowIndex then
    local top = (item.rowIndex - 1) * ROW_H
    if top < M.modScroll then M.modScroll = top end
    if top + ROW_H > M.modScroll + LIST_H then M.modScroll = top + ROW_H - LIST_H end
  end
end

-- Left / Right stay on the same row (tabs, games, Menu buttons, bottom bar)
-- and wrap around at either end.
local function rowOf(it)
  if it.kind == "tab" then return "tabs" end
  if it.kind == "card" then return "cards" end
  if it.kind == "menu" then return "menus" end
  if it.id and it.id:match("^bb_") then return "bottom" end
  return nil
end

function M:nav(dx, dy)
  if dx == 0 then return false end
  local items = M:build()
  local cur = UI.findItem(items, M.focus)
  local row = cur and rowOf(cur)
  if not row then return false end
  local list = {}
  for _, it in ipairs(items) do
    if rowOf(it) == row and not it.noFocus then list[#list + 1] = it end
  end
  table.sort(list, function(a, b) return a.x < b.x end)
  local at
  for i, it in ipairs(list) do if it == cur then at = i end end
  if not at or #list < 2 then return true end
  local nextIt = list[((at - 1 + dx) % #list) + 1]
  M.focus = nextIt.id
  M:onFocus(nextIt, "keys")
  return true
end

function M:wheel(dy)
  if Catalog.tabs[M.activeTab].id == "mods" then M.modScroll = M.modScroll - dy * 120 end
end

function M:stepTab(dir)
  local cur = M.focus and M.focus:match("^tab(%d)$")
  local i = tonumber(cur) or M.activeTab
  i = ((i - 1 + dir) % #Catalog.tabs) + 1
  M.focus = "tab" .. i
  M.menuOpen = nil
  if Catalog.tabs[i].id ~= "launch" then M.activeTab = i end
end

function M:back()
  if M.menuOpen then
    M.focus = "menu_" .. M.menuOpen
    M.menuOpen = nil
    return true
  end
  M.confirmExit()
  return true
end

function M:draw(items, focusId)
  UI.setColor(UI.colors.bg)
  love.graphics.rectangle("fill", 0, 0, UI.W, UI.H)
  local onLaunch = focusId == "tab" .. #Catalog.tabs
  for _, it in ipairs(items) do
    if it.kind == "tab" then
      local lit = onLaunch and it.tabIndex == #Catalog.tabs or (not onLaunch and it.tabIndex == M.activeTab)
      love.graphics.setLineWidth(4)
      UI.setColor(lit and UI.colors.tabActive or UI.colors.tab)
      love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 12, 12)
      UI.setColor(UI.colors.tabBorder)
      love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 12, 12)
      UI.textCentered(it.label, UI.pixel(44), it.x, it.y, it.w, it.h)
      if it.id == focusId then UI.focusRing(it) end
    elseif it.kind == "card" then
      drawCard(it, it.id == focusId)
    end
  end
  if Catalog.tabs[M.activeTab].id == "mods" then
    drawModsPanel(items, focusId)
    for _, it in ipairs(items) do
      if not it.kind and not it.modRow and not it.id:match("^bb_") then UI.button(it, it.id == focusId) end
    end
  end
  for _, it in ipairs(items) do
    if it.kind == "menu" then drawMenuButton(it, it.id == focusId) end
    if it.kind == "fsicon" then
      -- four arrows pointing out (go fullscreen) or in (go windowed)
      local cx, cy = it.x + it.w / 2, it.y + it.h / 2
      local full = love.window.getFullscreen()
      love.graphics.setLineWidth(3)
      UI.setColor(UI.colors.white)
      for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local ox, oy = cx + d[1] * 22, cy + d[2] * 20
        local ix, iy = cx + d[1] * 8, cy + d[2] * 7
        love.graphics.line(ix, iy, ox, oy)
        local tipX, tipY = full and ix or ox, full and iy or oy
        local sx, sy = full and d[1] or -d[1], full and d[2] or -d[2]
        love.graphics.line(tipX, tipY, tipX + sx * 9, tipY)
        love.graphics.line(tipX, tipY, tipX, tipY + sy * 9)
      end
      if it.id == focusId then UI.focusRing(it, 3) end
    end
  end
  for _, it in ipairs(items) do
    if it.kind == "dd" then drawDropItem(it, it.id == focusId) end
  end
  for _, it in ipairs(items) do
    if it.id:match("^bb_") then
      if it.kind == "plain" or it.kind == "swap" then drawPlain(it, it.id == focusId)
      else UI.button(it, it.id == focusId) end
    end
  end
  if not R.root then
    UI.textCentered("Gen1 Recomp folder not set yet - press any game's Menu or a card to pick it.",
      UI.sans(22), 0, 950, UI.W, 28, UI.colors.warn)
  end
end

return M
