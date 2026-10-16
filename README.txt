G1R FRONTEND - build 8

WHAT YOU NEED
  LOVE 11.5 (the same engine Gen1 Recomp uses): https://love2d.org
  - Windows: install LOVE 11.5, then double-click G1R-Frontend.love
    (or drag it onto love.exe).
  - Steam Deck / Linux: download the LOVE 11.5 AppImage, make it executable,
    and run:  ./love-11.5-x86_64.AppImage G1R-Frontend.love
    To use it in Game Mode, add the AppImage to Steam as a non-Steam game
    with G1R-Frontend.love (full path) as its launch option.

FIRST START
  The frontend looks for Gen1 Recomp next to itself. Put G1R-Frontend.love in
  your Gen1 Recomp folder, or pick the folder when it asks. It remembers it.

CONTROLS
  Keyboard  arrows move, Enter picks, Esc goes back, Page Up/Down change tab
  Gamepad   D-pad or left stick moves, A picks, B goes back, LB/RB change tab
            (the Confirm/Cancel button at the bottom left swaps A and B)
  Mouse     click, wheel scrolls lists, right-click goes back
  F11 or the arrows icon (top right) switches fullscreen / window
  Drop a picture on a game to use it as its art, a .sav on a game to import
  it, or a mod .zip anywhere to install it.  F5 re-reads everything.

WHAT RUNS WHERE
  Import, Export, Duplicate, Delete and ID Sync use Gen1 Recomp's own code,
  loaded from its newest update file (portable installs). If that can't be
  loaded, the frontend offers to open Gen1 Recomp's launcher instead.
  Edit save opens Gen1 Recomp's save editor directly. Settings shows Gen1
  Recomp's own settings list. Extras, the bug report and Save Sync accounts
  open Gen1 Recomp's launcher.

GOOD TO KNOW
  - Saves, Rename, C. Carts and the Mods tab change Gen1 Recomp's options.lua.
    Do those with Gen1 Recomp closed: it rewrites that file when it saves.
  - The frontend installs a tiny mod, "G1R Frontend Companion", into Gen1
    Recomp's mods folder. It makes closing a game started from the frontend
    close Gen1 Recomp too, instead of reopening Recomp's launcher. It does
    nothing when you start games from Recomp itself.
  - Updates download into Gen1 Recomp's updates folder; Recomp uses them the
    next time it starts.
  - Mods tab: Search filters your installed mods by name or description.
    Check for updates asks GitHub about every mod whose manifest names its
    repo ("github": "owner/repo"); mods with a newer release show
    "Update: vX" in yellow. Update all checks and then installs them all.
    GitHub allows about 60 checks an hour without an account.
