-- G1R Frontend Companion.
-- The frontend writes the time into session.txt (in this folder) just before
-- it starts a game. If that was moments ago, this game came from the
-- frontend, so leaving it should end Gen1 Recomp rather than open Recomp's
-- own launcher (the frontend is the launcher):
--   * closing the window: veto Recomp's "return to the launcher" step
--   * Gen 3's in-game EXIT: Gen 3 always hands that to the launcher, so the
--     hand-off is removed and the game quits like Gen 1 and 2 do.
return function(mod)
  local ok, body = pcall(mod.read, mod, "session.txt")
  local stamp = ok and tonumber(tostring(body or ""):match("%d+")) or nil
  if not stamp or math.abs(os.time() - stamp) > 600 then return end
  if not (mod.hooks and mod.hooks.wrap) then return end
  mod.hooks:wrap("core.quit_to_launcher", function()
    return false
  end, 1000)
  mod.hooks:wrap("core.update", function(nextFn, game, ...)
    if type(game) == "table" and rawget(game, "returnToLauncher") then
      game.returnToLauncher = nil
    end
    return nextFn(game, ...)
  end, 1000)
end
