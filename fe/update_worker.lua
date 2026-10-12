-- Runs on a separate thread so the frontend never freezes while talking to
-- GitHub. Uses curl, which comes with Windows 10+ and SteamOS / Linux.
--
-- In  (fe_update_in):  { id, cmd = "fetch", url }
--                      { id, cmd = "download", url, path, sumsUrl?, name? }
-- Out (fe_update_out): { id, ok, body | path | message }

require("love.data")
require("love.filesystem")

local inbox = love.thread.getChannel("fe_update_in")
local outbox = love.thread.getChannel("fe_update_out")
local windows = package.config:sub(1, 1) == "\\"

local function q(s) return '"' .. tostring(s):gsub('"', '') .. '"' end

local function fetch(url)
  local p = io.popen("curl -sL --max-time 60 -A G1R-Frontend " .. q(url), "r")
  if not p then return nil end
  local body = p:read("*a")
  p:close()
  if not body or body == "" then return nil end
  return body
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function writeFile(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function download(job)
  local want
  if job.sumsUrl then
    local sums = fetch(job.sumsUrl)
    for line in (sums or ""):gmatch("[^\r\n]+") do
      local h, file = line:match("^(%x+)%s+%*?(.-)%s*$")
      if h and file == job.name then want = h:lower() end
    end
    if not want then
      return { ok = false, message = "The release has no checksum for " .. tostring(job.name) ..
        ", so it wasn't downloaded." }
    end
  end
  local part = job.path .. ".part"
  os.remove(part)
  local cmd = "curl -sL --max-time 900 -A G1R-Frontend -o " .. q(part) .. " " .. q(job.url)
  if windows then cmd = '"' .. cmd .. '"' end
  os.execute(cmd)
  local data = readFile(part)
  os.remove(part)
  if not data or #data == 0 then return { ok = false, message = "The download didn't complete." } end
  if want and hex(love.data.hash("sha256", data)) ~= want then
    return { ok = false, message = "The download didn't match its checksum, so it was thrown away." }
  end
  if not writeFile(job.path, data) then
    return { ok = false, message = "Couldn't save the download to " .. job.path }
  end
  return { ok = true, path = job.path }
end

while true do
  local job = inbox:demand()
  local res
  if job.cmd == "fetch" then
    local body = fetch(job.url)
    res = body and { ok = true, body = body }
      or { ok = false, message = "Couldn't reach GitHub. Check your internet connection." }
  elseif job.cmd == "download" then
    res = download(job)
  else
    res = { ok = false, message = "unknown job" }
  end
  res.id = job.id
  outbox:push(res)
end
