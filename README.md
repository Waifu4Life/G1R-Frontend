# G1R Frontend

A launcher for [Gen1 Recomp](https://github.com/bryanthaboi/gen1recomp), built with LÖVE 11.5.
Pick your games from their box art, manage saves and mods, and update Gen1 Recomp,
with keyboard, mouse or gamepad.

## Features
- Gen 1 & 2, Gen 3 and Spin-Offs tabs with box art (bundled or your own pictures)
- Per-game Menu: Custom Art, Save Manager (import, export, duplicate, rename, edit, delete,
  new slot), Custom Cart, ID Sync
- Mods tab: per-game on/off, load order, updates and versions from GitHub, dependencies,
  install from .zip
- Gen1 Recomp's own Settings list, Save Sync status, shortcuts to Box, Online and Skins
- Check for Updates / Patch Notes, Open Game Folder
- Fullscreen or a remembered window; A/B swap for controllers

## Running it
1. Install [LÖVE 11.5](https://love2d.org).
2. Zip the contents of this folder (so `main.lua` is at the top of the zip) and rename it
   `G1R-Frontend.love`, or run `love .` from this folder.
3. On first start, point it at your Gen1 Recomp folder (or put the .love inside that folder).

Steam Deck / Linux: run it with the LÖVE 11.5 AppImage. Windows and Linux are supported.

## How it works with Gen1 Recomp
- Games start with Recomp's own launch options (`--game=`, `--cart=`).
- Saves, carts and mod settings are read from and written to Recomp's `options.lua`
  the same way Recomp does it. Change them while Recomp is closed.
- Import, export, duplicate, delete, ID Sync and Settings use Gen1 Recomp's own code,
  loaded at run time from the player's own Recomp install (portable installs). None of
  Recomp's code is included in this repository.
- `companion/` is a tiny Recomp mod the frontend installs so that leaving a game started
  from the frontend closes Recomp instead of reopening its launcher.

## Controls
| | Keyboard | Gamepad | Mouse |
|---|---|---|---|
| Move | Arrows | D-pad / left stick | Point |
| Pick | Enter | A | Click |
| Back | Esc | B | Right-click |
| Change tab | Page Up / Down | LB / RB | Click a tab |
| Fullscreen | F11 | | Icon at top right |

## Credits
- Frontend by Waifu4Life
- Gen1 Recomp Deluxe by bryanthaboi https://github.com/bryanthaboi
