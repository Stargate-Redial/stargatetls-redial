# What the installer does

`install.bat` runs `install.ps1` with Windows PowerShell. Everything it does can also be done by hand, as below.

## Where things are

| | Found from | Default |
|---|---|---|
| Steam | registry `HKCU\Software\Valve\Steam\SteamPath` | `C:\Program Files (x86)\Steam` |
| The mod | registry `SourceModInstallPath` + `sgtls` | `Steam\steamapps\sourcemods\sgtls` |

`-ModDir` overrides it. The installer stops if Stargate: The Last Stand is running (it would lock the files).

## 1. Bot files

`payload\` is copied into the mod's folder:

| File | What |
|---|---|
| `addons\botrix.dll` | the bot plugin (release zip only) |
| `addons\botrix.vdf` | tells the engine to load `addons\botrix` |
| `addons\botrix\config.ini` | bot settings: weapons, classes, equipment, skills |
| `addons\botrix\waypoints\*.way` | the paths of the 3 maps |
| `materials\console\background01.vtf`, `background01_widescreen.vtf` | the menu backgrounds with "REDIAL V1.0.0" (release zip only; not with `-NoSplash`) |

A file that already exists and differs is first copied to `sgtls\redial-backup\` (same relative path). `redial-backup\installed.txt` lists every file installed: `A` added, `R` replaced, `C` cfg created.

## 2. cfg\listenserver.cfg and cfg\server.cfg

This block is added at the end of both: `listenserver.cfg` is run for a game created from the menu, `server.cfg` on a dedicated server. The files keep their own line endings, and the uninstaller removes only this block:

```
// >>> Stargate Redial bots (added by install.bat; uninstall.bat removes this block)
// Botrix bots (addons/botrix): players + bots kept at this total, bots balance the teams.
botrix config bot quota 10
// Bot skill range: fool stupied normal smart pro.
botrix config bot intelligence normal smart
// <<< Stargate Redial bots
```

A map can have its own total in `cfg\botrix_<map>.cfg` (e.g. `botrix config bot quota 14`), which the plugin runs after the server's cfg.

## Uninstall

`uninstall.bat` reads `installed.txt`. It puts back the `R` files, deletes the `A` files and the folders they leave empty, and removes the cfg blocks. Then it deletes `redial-backup`.

## By hand

1. Copy `payload\*` into `steamapps\sourcemods\sgtls`.
2. Add the lines of section 2 to `cfg\listenserver.cfg` and `cfg\server.cfg`.

To check the bots loaded: `plugin_print` in the console lists Botrix.

## Bot commands

| Command | Effect |
|---|---|
| `botrix config bot quota N` | players + bots kept at N (0 = off) |
| `botrix config bot intelligence MIN MAX` | skill range of new bots: fool, stupied, normal, smart, pro |
| `botrix bot add` | add a bot |
| `botrix bot kick all` | remove every bot |
| `botrix bot` | all bot commands |
| `sgtls_objectives` | what the bots know about the map: objectives, buttons, teleporters |

Botrix writes its log to `addons\botrix\botrix.log`.
