# Hosting a Stargate: The Last Stand Linux dedicated server

The Stargate Redial server (`92.222.243.147:27031`) runs this way, natively on Debian 13, with no Wine and no emulation. With 10 bots it uses about 15 % of one vCPU and 170 MB.

The engine and the game content belong to Valve and are not in this repository: you fetch them yourself, as below. The files referred to as `linux/...` are in this repository, and the built ones are in the `linux` folder of the release zip.

You need a 64-bit Linux with 32-bit support (Debian: `dpkg --add-architecture i386 && apt install lib32gcc-s1 lib32stdc++6`), `screen`, SteamCMD, and Python 3 for the tools.

## 1. The engine: Source 2007 "orangebox" for Linux

SteamCMD app 310 (Source 2007 Dedicated Server), Linux depot 311, downloads anonymously:

```
steamcmd +login anonymous +download_depot 310 311 +quit
```

It holds 60 files (31 MB): `srcds_i486`, `srcds_run`, `bin/*.so` and a minimal `hl2/` (2014 build, `engine_i486.so` MD5 `99d41901…`). It needs no Steam client: the file system is built into `dedicated_i486.so`. Move them to a folder named **`orangebox`**: Botrix recognises the game by the name of the folder that holds the srcds executable (`games =` in `addons/botrix/config.ini`).

## 2. Engine fixes

1. **Steam client.** The 2014 `bin/steamclient_i486.so` can't log on any more ("Could not establish connection to Steam servers"). Replace it with a link to the `linux32/steamclient.so` of a current SteamCMD (`~/.steam/sdk32/steamclient.so` once SteamCMD has run). It still serves the old interfaces that `steam_api` asks for. Keep the original as `.2014`. The "Unable to load Steam library." line left in the console is harmless.
2. **Ghost players: `bin/srcds2007_fix_i486.so`,** preloaded (`LD_PRELOAD`). Source: `linux/srcds2007_fix.c`; build with `gcc -m32 -shared -fPIC -O2 -o srcds2007_fix_i486.so srcds2007_fix.c -ldl`, or take it from the release zip.
   - The engine registers every bot with Steam when it joins (`CSteam3::NotifyLocalClientConnect`), but `CSteam3::NotifyClientDisconnect` returns at once for fake clients, before the code written to unregister them. Steam's player list, which answers the server browser, keeps every bot that ever left: 10 more "players" at each map change with 10 bots, while `status` shows 10.
   - The library wraps `dlopen`. Once `engine_i486.so` is loaded, it checks the 7 bytes at `NotifyClientDisconnect+0x76` (`ff 57 70 84 c0 75 dd`) and turns that early `jne` into two `nop`s. Another engine build is left alone, and the console says so.

With these, the console shows "Connection to Steam servers successful" and "VAC secure mode is activated", and the server appears in the Steam list (app 218, `sgtls`).

## 3. Half-Life 2 content

The 2014 engine can't read VPK files: extract what a server needs with `linux/vpk.py`. Take the VPKs from a Source SDK Base 2007 install (`steamapps/common/Source SDK Base 2007/vpks`), in this search order: depot 215 into `orangebox/sourcetest/`, then 305, 306, 307, 206, 207 and 208 into `orangebox/hl2/`:

```
python3 -I vpk.py extract orangebox/sourcetest server <depot 215 _dir.vpk>
python3 -I vpk.py extract orangebox/hl2 server <depot 305 _dir.vpk> <306> <307> <206> <207> <208>
```

The `server` filter leaves out textures, sounds of voices and music, videos and interface files, and keeps the `.dx90.vtx` model files (without them the server logs "MDLCache: Failed load of .VTX data" in a loop). `hl2/` ends up at about 620 MB, `sourcetest/` at 63 MB.

## 4. The mod

1. Copy `sourcemods/sgtls` from a client install. Leave out the `.vtf` textures, logs, `bin/*.dll`, `media/`, `screenshots/`, `SAVE/`, `DownloadLists/` and the uninstaller. It's about 400 MB.
2. Put the Linux game DLL in `sgtls/bin/server_i486.so`. It comes from the mod's server edition (`sgtls_server_beta11_full.zip` on the mod's [ModDB page](https://www.moddb.com/mods/stargate-the-last-stand/downloads), MD5 of the `.so` `912fe17c…`). It's the same build as the client's `server.dll`.
3. Bots, from the release zip:
   - `linux/addons/botrix_i486.so` → `sgtls/addons/botrix_i486.so`;
   - `payload/addons/botrix.vdf` and `payload/addons/botrix/` (settings and waypoints) → into `sgtls/`;
   - the bot block of [DETAILS.md](DETAILS.md#2-cfglistenservercfg-and-cfgservercfg) at the end of `sgtls/cfg/server.cfg`.
4. In `sgtls/cfg/server.cfg`, also set `hostname`, `sv_lan 0`, `log on` and `sv_logflush 1` (each log line written at once). Keep the RCON password out of it: `exec rcon.cfg`, with `rcon_password` in a `cfg/rcon.cfg` readable only by the server's user. The mod's own `server.cfg` sets `mp_cloaktime` and `mp_cloakchargetime`, which the engine refuses in multiplayer: harmless, as on Windows.

## 5. Run

`linux/run-server.sh` starts srcds in a loop that restarts it after a crash. Copy it next to the `orangebox` folder and set its variables (or pass them in the environment): `SRCDS_DIR`, `IP`, `PORT`, `CLIENTPORT`, `MAXPLAYERS`, `MAP`. `linux/sgtls.service` is a systemd unit that runs it in a `screen`.

- Open the game port in UDP in your firewall.
- Give it 32 slots: with fewer, the mod closes parts of some maps.
- `-nohltv` is set: SourceTV isn't needed, and its port (27020) is often taken by another server.
- Set `IP`: without `-ip`, the engine binds to the address of the host name, which can be `127.0.1.1`.
- The engine ignores A2S queries (server browser) that come from `127.0.0.1`: a monitoring script must query the public address.
- `linux/a2s.py host port` queries the server like the browser does; `linux/rcon.py host port - "status"` runs an RCON command, with the password in `RCON_PASSWORD`.

"proxy not found" messages for materials are normal on a dedicated server.

## 6. How the Linux port of the bots works

The Windows port finds the game's functions and fields by address and offset in `server.dll`. On Linux, everything is in the `#elif defined(__linux__)` branches of the patch and in `mods/sgtls/linux_server.cpp`:

- **Symbols.** The mod's `server_i486.so` (GCC) exports all its symbols, so functions are found by `dlsym` with their mangled names. The module is found by `dladdr` on the game's interface, or by its file name.
- **Vtables.** An object's vtable pointer is 2 entries after the `_ZTV…` symbol (offset-to-top and typeinfo); `dladdr1` gives the symbol's size to bound slot searches. The `.so` has text relocations, so its vtables are in the read-only text segment: they are written through `mprotect`.
- **Calling convention.** GCC's `thiscall` is `cdecl` with `this` first.
- **What the port patches** works the same on both systems: the spawn point guard (slot 341 of the GCC vtable of `CTLSPlayer`), a `ret` over the SDK test bots' `Bot_RunAll`, and `UseEntity` through `CBaseEntity::Use` for buttons.
- Windows only: the crash logger (`crash_handler.cpp`) and the `sgtls_equipids` debug command.

Build: [BUILDING.md](BUILDING.md#linux). The plugin links its own static libstdc++ before `tier0_i486.so` (which exports an old one) and uses `-Bsymbolic`, so that its globals (`g_pCVar`...) are its own.
