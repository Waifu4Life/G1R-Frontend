-- Reading and writing the data files the frontend shares with Gen1 Recomp.
--
-- encode() writes exactly the format Recomp's own SaveSerializer writes
-- ("return { key = value, ... }" with sorted keys and %q strings), so
-- options.lua stays byte-for-byte in the shape Recomp expects.
-- decodeLua() reads such a file in an empty sandbox: only plain data can
-- come out of it.
-- decodeJson() reads manifest.json files and GitHub's release info.

local S = {}

local function serialize(v, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local t = type(v)
  if t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return a < b
    end)
    if next(v) == nil then return "{}" end
    local parts = {}
    for _, k in ipairs(keys) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. serialize(k) .. "]"
      end
      parts[#parts + 1] = pad .. "  " .. key .. " = " .. serialize(v[k], indent + 1)
    end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. pad .. "}"
  end
  error("cannot serialize " .. t)
end
if jit and jit.off then jit.off(serialize, true) end

function S.encode(data)
  return "return " .. serialize(data) .. "\n"
end

function S.decodeLua(str)
  if type(str) ~= "string" or str == "" then return nil, "empty" end
  if str:byte(1) == 27 then return nil, "not a text file" end
  local fn, err = loadstring(str, "=data")
  if not fn then return nil, err end
  setfenv(fn, {})
  local ok, result = pcall(fn)
  if not ok then return nil, result end
  if type(result) ~= "table" then return nil, "not a table" end
  return result
end

function S.deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local copy = {}
  seen[v] = copy
  for k, val in pairs(v) do copy[S.deepCopy(k, seen)] = S.deepCopy(val, seen) end
  return copy
end

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------
local function jsonError(str, i, msg)
  error(("JSON error at %d: %s"):format(i, msg), 0)
end

local decodeValue

local function skip(str, i)
  return str:find("[^ \t\r\n]", i) or (#str + 1)
end

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000),
      0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f",
  n = "\n", r = "\r", t = "\t" }

local function decodeString(str, i)
  local out = {}
  local j = i + 1
  while true do
    local c = str:sub(j, j)
    if c == "" then jsonError(str, j, "unfinished string") end
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local e = str:sub(j + 1, j + 1)
      if e == "u" then
        local hex = str:sub(j + 2, j + 5)
        local cp = tonumber(hex, 16) or 63
        j = j + 6
        if cp >= 0xD800 and cp <= 0xDBFF and str:sub(j, j + 1) == "\\u" then
          local lo = tonumber(str:sub(j + 2, j + 5), 16)
          if lo and lo >= 0xDC00 and lo <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            j = j + 6
          end
        end
        out[#out + 1] = utf8char(cp)
      else
        out[#out + 1] = ESC[e] or e
        j = j + 2
      end
    else
      local k = str:find('["\\]', j)
      if not k then jsonError(str, j, "unfinished string") end
      out[#out + 1] = str:sub(j, k - 1)
      j = k
    end
  end
end

decodeValue = function(str, i)
  i = skip(str, i)
  local c = str:sub(i, i)
  if c == "{" then
    local obj = {}
    i = skip(str, i + 1)
    if str:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      i = skip(str, i)
      if str:sub(i, i) ~= '"' then jsonError(str, i, "expected a key") end
      local key
      key, i = decodeString(str, i)
      i = skip(str, i)
      if str:sub(i, i) ~= ":" then jsonError(str, i, "expected ':'") end
      local val
      val, i = decodeValue(str, i + 1)
      obj[key] = val
      i = skip(str, i)
      local d = str:sub(i, i)
      if d == "}" then return obj, i + 1 end
      if d ~= "," then jsonError(str, i, "expected ',' or '}'") end
      i = i + 1
    end
  elseif c == "[" then
    local arr = {}
    i = skip(str, i + 1)
    if str:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local val
      val, i = decodeValue(str, i)
      arr[#arr + 1] = val
      i = skip(str, i)
      local d = str:sub(i, i)
      if d == "]" then return arr, i + 1 end
      if d ~= "," then jsonError(str, i, "expected ',' or ']'") end
      i = i + 1
    end
  elseif c == '"' then
    return decodeString(str, i)
  elseif str:sub(i, i + 3) == "true" then return true, i + 4
  elseif str:sub(i, i + 4) == "false" then return false, i + 5
  elseif str:sub(i, i + 3) == "null" then return nil, i + 4
  else
    local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not num or num == "" then jsonError(str, i, "unexpected character") end
    return tonumber(num), i + #num
  end
end

function S.decodeJson(str)
  if type(str) ~= "string" then return nil, "no data" end
  -- skip a UTF-8 byte-order mark
  if str:sub(1, 3) == "\239\187\191" then str = str:sub(4) end
  local ok, result = pcall(decodeValue, str, 1)
  if not ok then return nil, result end
  return result
end

return S
