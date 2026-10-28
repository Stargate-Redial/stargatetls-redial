# Building from source

The bots are [Botrix](https://github.com/borzh/botrix) by Boris Godin, with a port to the two Stargate Source mods. The same source builds four plugins:

| Target | Game | Engine | hl2sdk branch | Output |
|---|---|---|---|---|
| `ob` | Stargate: The Last Stand | Source 2007 (Source SDK Base 2007) | `orangebox` | Windows `botrix.dll`, Linux `botrix_i486.so` |
| `ep1` | StargateTC 2 | Source 2006 (Source SDK Base 2006) | `episode1` | Windows `botrix.dll`, Linux `botrix_i486.so` |

The port is `src/botrix_stargate.patch`, against Botrix at the commit in `src/BASE_COMMIT.txt`. The patch is the same in the StargateTC 2 and Stargate TLS repositories.

## Get the sources

```
git clone -c core.autocrlf=false https://github.com/borzh/botrix.git
cd botrix
git checkout 54fa2fa610f9ad8b306aafb82337b60ac3dbf346
git apply ../src/botrix_stargate.patch
cd ..
git clone -b orangebox https://github.com/alliedmodders/hl2sdk.git hl2sdk-ob
git clone -b episode1 https://github.com/alliedmodders/hl2sdk.git hl2sdk-ep1
```

Clone Botrix with `core.autocrlf=false`: some of its files have CRLF line endings and others LF, and the patch matches them byte for byte. The release was built with hl2sdk `orangebox` at `88bc34a` and `episode1` at `4b0cde2`.

## Windows

Visual Studio 2022 (C++ desktop workload, x86 tools) and Python 3:

```
py tools\build_windows.py ob  --src botrix --sdk hl2sdk-ob  --out build-ob
py tools\build_windows.py ep1 --src botrix --sdk hl2sdk-ep1 --out build-ep1
```

Pass `--vcvars <path>\vcvars32.bat` if Visual Studio isn't in its default folder. The compiler writes source paths into the DLL (`__FILE__` in log messages): for a DLL you publish, build from a short neutral path, e.g. `subst W: <folder>` and `--src W:\botrix`.

The plugin goes to `<mod>\addons\botrix.dll`.

## Linux

Debian or Ubuntu with `g++-multilib` and Python 3:

```
python3 tools/build_linux.py ob  --src botrix --sdk hl2sdk-ob  --out build-linux-ob
python3 tools/build_linux.py ep1 --src botrix --sdk hl2sdk-ep1 --out build-linux-ep1
```

The plugin goes to `<mod>/addons/botrix_i486.so` (the engine adds `_i486.so` to the name in `addons/botrix.vdf`). Release builds are stripped with `strip --strip-debug`. How the Linux port works, and the dedicated server itself: [LINUX_SERVER.md](LINUX_SERVER.md).

## Menu background

`tools/redial_splash.py` stamps "REDIAL V<version>" on the mods' menu backgrounds (`materials/console/background01*.vtf`). It needs Pillow and the Perpetua Titling fonts of Windows:

```
py tools\redial_splash.py "<Steam>\steamapps\sourcemods" out 1.0.0
```

It reads the original textures of each installed mod (not already stamped ones) and writes the stamped ones to `out\<mod>\materials\console`, plus previews. The release zip carries them in `payload\materials\console`.

## Installer tests

```
powershell -ExecutionPolicy Bypass -File tests\test-installer.ps1 -PackageDir <extracted release zip>
powershell -ExecutionPolicy Bypass -File tests\test-installer.ps1 -PackageDir <extracted release zip> -Shell pwsh
```

They install, reinstall and uninstall on a fake Steam layout in a temporary folder, and check that every original file comes back.
