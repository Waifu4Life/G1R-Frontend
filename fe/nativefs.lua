-- Native file access for the frontend.
--
-- LOVE's own love.filesystem can only write inside the frontend's save folder,
-- but the frontend has to read and write Gen1 Recomp's folder (options.lua,
-- saves, mods, carts). Plain Lua io.* handles reading and writing files;
-- listing folders, making folders and starting programs go through LuaJIT's
-- FFI so nothing ever flashes a console window on Windows.
--
-- Paths are kept with forward slashes everywhere ("C:/Games/G1R" on
-- Windows); Windows accepts them for every call used here except
-- ShellExecute, which gets backslashes.

local ffi = require("ffi")
local bit = require("bit")

local M = {}
M.windows = ffi.os == "Windows"

local C = ffi.C
local shell32

if M.windows then
  pcall(ffi.cdef, [[
    typedef struct { uint32_t lo, hi; } FE_FILETIME;
    typedef struct {
      uint32_t attr;
      FE_FILETIME created, accessed, written;
      uint32_t sizeHigh, sizeLow, reserved0, reserved1;
      char name[260];
      char altName[14];
    } FE_FINDDATA;
    void* FindFirstFileA(const char* pattern, FE_FINDDATA* data);
    int FindNextFileA(void* handle, FE_FINDDATA* data);
    int FindClose(void* handle);
    uint32_t GetFileAttributesA(const char* path);
    int CreateDirectoryA(const char* path, void* security);
    int RemoveDirectoryA(const char* path);
    uint32_t GetLogicalDrives(void);
    int SetEnvironmentVariableA(const char* name, const char* value);
    void* ShellExecuteA(void* hwnd, const char* op, const char* file,
                        const char* params, const char* dir, int show);
  ]])
  pcall(function() shell32 = ffi.load("shell32") end)
else
  pcall(ffi.cdef, [[
    struct fe_dirent {
      uint64_t d_ino;
      int64_t d_off;
      unsigned short d_reclen;
      unsigned char d_type;
      char d_name[256];
    };
    void* opendir(const char* name);
    struct fe_dirent* readdir(void* dir);
    int closedir(void* dir);
    int mkdir(const char* path, unsigned int mode);
    int rmdir(const char* path);
  ]])
end

local INVALID = M.windows and ffi.cast("void*", -1) or nil

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------
function M.norm(p)
  if type(p) ~= "string" or p == "" then return p end
  p = p:gsub("\\", "/")
  if #p > 1 then p = p:gsub("/+$", "") end
  if M.windows and p:match("^%a:$") then p = p .. "/" end
  return p
end

function M.join(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

function M.parent(p)
  p = M.norm(p)
  if p == "/" or (M.windows and p:match("^%a:/$")) then return nil end
  local par = p:match("^(.*)/[^/]+$")
  if not par then return nil end
  if par == "" then return "/" end
  if M.windows and par:match("^%a:$") then return par .. "/" end
  return par
end

function M.basename(p)
  return M.norm(p):match("([^/]+)$") or p
end

function M.ext(p)
  local e = tostring(p):match("%.([%w]+)$")
  return e and e:lower() or nil
end

local function winPath(p) return (p:gsub("/", "\\")) end
M.winPath = winPath

---------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------
function M.read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

function M.write(path, data)
  local f, err = io.open(path, "wb")
  if not f then return false, err end
  local ok, werr = f:write(data)
  f:close()
  if not ok then return false, werr end
  return true
end

function M.isDir(path)
  path = M.norm(path)
  if M.windows then
    local attr = C.GetFileAttributesA(path)
    if attr == 0xFFFFFFFF then return false end
    return bit.band(attr, 0x10) ~= 0
  end
  local d = C.opendir(path)
  if d == nil then return false end
  C.closedir(d)
  return true
end

function M.isFile(path)
  if M.isDir(path) then return false end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function M.exists(path)
  return M.isFile(path) or M.isDir(path)
end

function M.remove(path)
  return os.remove(path)
end

function M.mkdir(path)
  path = M.norm(path)
  if M.isDir(path) then return true end
  if M.windows then
    return C.CreateDirectoryA(path, nil) ~= 0 or M.isDir(path)
  end
  return C.mkdir(path, 493) == 0 or M.isDir(path)   -- 0755
end

-- Make a folder and every missing parent.
function M.mkdirp(path)
  path = M.norm(path)
  if M.isDir(path) then return true end
  local par = M.parent(path)
  if par and not M.isDir(par) then
    if not M.mkdirp(par) then return false end
  end
  return M.mkdir(path)
end

function M.rmdir(path)
  path = M.norm(path)
  if M.windows then return C.RemoveDirectoryA(path) ~= 0 end
  return C.rmdir(path) == 0
end

-- Delete a folder and everything in it. Refuses very short paths.
function M.removeTree(path)
  path = M.norm(path)
  if #path < 6 or path == M.home() then return false end
  for _, e in ipairs(M.list(path, true)) do
    local p = M.join(path, e.name)
    if e.dir then M.removeTree(p) else os.remove(p) end
  end
  return M.rmdir(path)
end

-- Show a folder in Explorer / the Linux file manager.
function M.openFolder(path)
  path = M.norm(path)
  if M.windows then
    if not shell32 then return false, "shell32 unavailable" end
    local r = shell32.ShellExecuteA(nil, "open", winPath(path), nil, nil, 1)
    local code = tonumber(ffi.cast("intptr_t", r))
    return code and code > 32, "Windows couldn't open the folder"
  end
  os.execute("(xdg-open '" .. path:gsub("'", "'\\''") .. "' >/dev/null 2>&1 &)")
  return true
end

-- Copy one file (whole file in memory; fine for saves, art and mods).
function M.copy(from, to)
  local data = M.read(from)
  if not data then return false, "can't read " .. from end
  return M.write(to, data)
end

---------------------------------------------------------------------------
-- Folder listing: { { name = "x", dir = true/false }, ... } sorted with
-- folders first, then by name (case-insensitive). Hidden entries
-- (starting with ".") are skipped unless showHidden.
---------------------------------------------------------------------------
function M.list(dir, showHidden)
  dir = M.norm(dir)
  local out = {}
  if M.windows then
    local data = ffi.new("FE_FINDDATA")
    local h = C.FindFirstFileA(M.join(dir, "*"), data)
    if h == nil or h == INVALID then return out end
    repeat
      local name = ffi.string(data.name)
      if name ~= "." and name ~= ".." then
        local hidden = bit.band(data.attr, 0x2) ~= 0 or name:sub(1, 1) == "."
        if showHidden or not hidden then
          out[#out + 1] = { name = name, dir = bit.band(data.attr, 0x10) ~= 0 }
        end
      end
    until C.FindNextFileA(h, data) == 0
    C.FindClose(h)
  else
    local d = C.opendir(dir)
    if d == nil then return out end
    while true do
      local e = C.readdir(d)
      if e == nil then break end
      local name = ffi.string(e.d_name)
      if name ~= "." and name ~= ".." and (showHidden or name:sub(1, 1) ~= ".") then
        local t = e.d_type
        local isDir
        if t == 4 then isDir = true
        elseif t == 8 then isDir = false
        else isDir = M.isDir(M.join(dir, name)) end   -- unknown type or a link
        out[#out + 1] = { name = name, dir = isDir }
      end
    end
    C.closedir(d)
  end
  table.sort(out, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

function M.home()
  if M.windows then
    return M.norm(os.getenv("USERPROFILE") or "C:/")
  end
  return M.norm(os.getenv("HOME") or "/")
end

-- Starting points for the file browser: drives on Windows, / and home on Linux.
function M.roots()
  local out = {}
  if M.windows then
    local mask = C.GetLogicalDrives()
    for i = 0, 25 do
      if bit.band(mask, bit.lshift(1, i)) ~= 0 then
        out[#out + 1] = string.char(65 + i) .. ":/"
      end
    end
  else
    out[1] = "/"
  end
  return out
end

-- The OS folder where LOVE games keep their data, for an identity.
function M.loveSaveDirs(identity)
  local out = {}
  if M.windows then
    local appdata = os.getenv("APPDATA")
    if appdata then
      out[#out + 1] = M.join(M.norm(appdata), identity)
      out[#out + 1] = M.join(M.join(M.norm(appdata), "LOVE"), identity)
    end
  else
    local xdg = os.getenv("XDG_DATA_HOME")
    local base = xdg and M.norm(xdg) or M.join(M.home(), ".local/share")
    out[#out + 1] = M.join(base, identity)
    out[#out + 1] = M.join(M.join(base, "love"), identity)
  end
  return out
end

---------------------------------------------------------------------------
-- Start another program without waiting for it.
---------------------------------------------------------------------------
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- env: optional { NAME = "value" } set only for the started program.
function M.launch(exe, args, cwd, env)
  args = args or {}
  cwd = cwd or M.parent(exe) or "."
  if M.windows then
    if not shell32 then return false, "shell32 unavailable" end
    -- the child copies our environment when it starts, so set, start, unset
    for k, v in pairs(env or {}) do C.SetEnvironmentVariableA(k, tostring(v)) end
    local parts = {}
    for i, a in ipairs(args) do
      a = tostring(a)
      parts[i] = a:find("[%s\"]") and ('"' .. a:gsub('"', '') .. '"') or a
    end
    local params = table.concat(parts, " ")
    local r = shell32.ShellExecuteA(nil, "open", winPath(exe), params, winPath(cwd), 1)
    for k in pairs(env or {}) do C.SetEnvironmentVariableA(k, nil) end
    local code = tonumber(ffi.cast("intptr_t", r))
    if code and code > 32 then return true end
    return false, "Windows refused to start it (code " .. tostring(code) .. ")"
  end
  local quoted = {}
  for i, a in ipairs(args) do quoted[i] = shq(a) end
  local prefix = ""
  for k, v in pairs(env or {}) do
    if tostring(k):match("^[%w_]+$") then prefix = prefix .. k .. "=" .. shq(v) .. " " end
  end
  local cmd = string.format("cd %s && (%s%s %s >/dev/null 2>&1 &)",
    shq(cwd), prefix, shq(exe), table.concat(quoted, " "))
  os.execute(cmd)
  return true
end

return M
