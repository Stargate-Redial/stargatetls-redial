"""Build the Botrix plugin for Windows (32-bit) with MSVC, for one of the two Stargate Source mods.

    py build_windows.py ob|ep1 --src <botrix> --sdk <hl2sdk> [--out <dir>] [--vcvars <vcvars32.bat>]

  ob   Stargate: The Last Stand (Source SDK Base 2007): hl2sdk branch "orangebox"
  ep1  StargateTC 2 (Source SDK Base 2006): hl2sdk branch "episode1"

<botrix> is github.com/borzh/botrix at src/BASE_COMMIT.txt with src/botrix_stargate.patch applied, <hl2sdk> the
AlliedModders hl2sdk checkout of the matching branch (see docs/BUILDING.md). Output: <out>/botrix.dll (+ .pdb).

The compiler records source paths (__FILE__) in the DLL: build from a short neutral path (e.g. a drive made with
`subst`) if the DLL is to be published.
"""
import argparse
import glob
import os
import subprocess
import sys

DEFAULT_VCVARS = r'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat'

ap = argparse.ArgumentParser()
ap.add_argument('target', choices=['ob', 'ep1'])
ap.add_argument('--src', required=True)
ap.add_argument('--sdk', required=True)
ap.add_argument('--out')
ap.add_argument('--vcvars', default=DEFAULT_VCVARS)
a = ap.parse_args()
SRC = os.path.abspath(a.src)
SDK = os.path.abspath(a.sdk)
OUT = os.path.abspath(a.out or os.path.join(os.getcwd(), 'build-' + a.target))
os.makedirs(OUT, exist_ok=True)

if a.target == 'ob':
    incs = ['.', 'public', 'public/engine', 'public/tier0', 'public/tier1', 'public/game/server', 'public/mathlib',
            'public/vstdlib', 'game/server', 'game/server/hl2', 'game/server/hl2mp', 'game/shared', 'common']
    defs = ['BOTRIX_SOURCE_ENGINE_2007', 'BOTRIX_TF2', 'BOTRIX_SGTLS']
    mod_dirs = ['sgtls']
    extra_files = ['mods/tf2/bot_tf2.cpp', 'mods/tf2/mod_tf2.cpp']
else:
    # StargateTC 2 shares the SGTLS helpers and crash logger.
    incs = ['.', 'public', 'public/engine', 'public/tier0', 'public/tier1', 'public/dlls', 'public/mathlib',
            'public/vstdlib', 'dlls', 'dlls/hl2_dll', 'dlls/hl2mp_dll', 'game_shared', 'game_shared/hl2mp']
    defs = ['BOTRIX_SOURCE_ENGINE_2006', 'BOTRIX_NO_COMMAND_COMPLETION', 'BOTRIX_SGTC2']
    mod_dirs = ['sgtc2']
    extra_files = ['mods/sgtls/crash_handler.cpp', 'mods/sgtls/sgtls_util.cpp', 'mods/sgtls/sgtls_map.cpp',
                   'mods/sgtls/objectives_sgtls.cpp']
defs += ['BOTRIX_HL2DM', 'BOTRIX_BOT_AIM_ERROR', 'GOOD_INI_ONE_KV_SEPARATOR', 'GOOD_INI_ONE_COMMENT_CHAR',
         'GOOD_LOG_FLUSH', 'GOOD_LOG_USE_ENDL', 'VECTOR', 'GAME_DLL', 'HL2_DLL', 'HL2_MP', 'HL2_EPISODIC', 'MP_SDK',
         'VPC', 'WIN32', '_WIN32', '_WINDOWS', 'NDEBUG', '_HAS_ITERATOR_DEBUGGING=0', '_ITERATOR_DEBUG_LEVEL=0',
         'COMPILER_MSVC', 'COMPILER_MSVC32', '_CRT_SECURE_NO_WARNINGS', '_CRT_NONSTDC_NO_DEPRECATE',
         '_ALLOW_KEYWORD_MACROS', '_ALLOW_RUNTIME_LIBRARY_MISMATCH']
files = ['good/src/file.cpp', 'good/src/ini_file.cpp', 'good/src/log.cpp', 'good/src/mutex.cpp', 'good/src/process.cpp',
         'good/src/thread.cpp', 'bot.cpp', 'chat.cpp', 'clients.cpp', 'config.cpp', 'console_commands.cpp', 'event.cpp',
         'item.cpp', 'mod.cpp', 'players.cpp', 'server_plugin.cpp', 'source_engine.cpp', 'type2string.cpp',
         'waypoint.cpp', 'waypoint_navigator.cpp', 'weapon.cpp', 'mods/hl2dm/bot_hl2dm.cpp', 'mods/hl2dm/mod_hl2dm.cpp']
files += extra_files
for d in mod_dirs:
    files += sorted(os.path.relpath(f, SRC).replace(os.sep, '/') for f in glob.glob(os.path.join(SRC, 'mods', d, '*.cpp')))


def q(p):
    return '"%s"' % os.path.normpath(p)


cl = ['/nologo', '/c', '/MP8', '/MT', '/O2', '/Oy-', '/Zi', '/EHsc', '/GR', '/W3', '/wd4005', '/wd4244', '/wd4267',
      '/wd4305', '/wd4996', '/wd4018', '/wd4800', '/Zc:threadSafeInit-', '/std:c++14', '/FS']
cl += ['/I' + q(SRC), '/I' + q(os.path.join(SRC, 'good/include'))] + ['/I' + q(os.path.join(SDK, i)) for i in incs]
cl += ['/D' + d for d in defs]
# /Fo"dir/": a trailing backslash before the quote would escape it.
cl += ['/Fo"%s/"' % os.path.normpath(OUT), '/Fd' + q(os.path.join(OUT, 'vc.pdb'))]
cl += [q(os.path.join(SRC, f)) for f in files]
# /PDBALTPATH: only the PDB's file name goes into the DLL, not the build path.
lk = ['/nologo', '/DLL', '/DEBUG', '/PDBALTPATH:%_PDB%', '/OPT:REF',
      '/OUT:' + q(os.path.join(OUT, 'botrix.dll')), '/PDB:' + q(os.path.join(OUT, 'botrix.pdb')),
      '/LIBPATH:' + q(os.path.join(SDK, 'lib', 'public'))]
lk += ['tier0.lib', 'tier1.lib', 'mathlib.lib', 'vstdlib.lib', 'legacy_stdio_definitions.lib', 'user32.lib',
       'advapi32.lib', '/NODEFAULTLIB:LIBC', '/NODEFAULTLIB:LIBCD', '/NODEFAULTLIB:LIBCMTD']
for o in glob.glob(os.path.join(OUT, '*.obj')):
    os.remove(o)
open(os.path.join(OUT, 'cl.rsp'), 'w').write('\n'.join(cl))
bat = os.path.join(OUT, 'run.bat')
open(bat, 'w').write('@echo off\r\ncall "%s" >nul\r\ncl @"%s" || exit /b 1\r\nexit /b 0\r\n'
                     % (a.vcvars, os.path.join(OUT, 'cl.rsp')))
r = subprocess.run(['cmd', '/c', bat], capture_output=True, text=True, encoding='oem', errors='replace')
log = r.stdout + r.stderr
if r.returncode == 0:
    lk += [q(o) for o in sorted(glob.glob(os.path.join(OUT, '*.obj')))]
    open(os.path.join(OUT, 'link.rsp'), 'w').write('\n'.join(lk))
    open(bat, 'w').write('@echo off\r\ncall "%s" >nul\r\nlink @"%s" || exit /b 1\r\necho BUILD OK\r\n'
                         % (a.vcvars, os.path.join(OUT, 'link.rsp')))
    r = subprocess.run(['cmd', '/c', bat], capture_output=True, text=True, encoding='oem', errors='replace')
    log += r.stdout + r.stderr
open(os.path.join(OUT, 'build.log'), 'w', encoding='utf8').write(log)
errs = [l for l in log.splitlines() if 'error C' in l or 'error LNK' in l or 'fatal error' in l]
for l in dict.fromkeys(errs):
    print(l[:400])
ok = 'BUILD OK' in log
print('BUILD OK:' if ok else 'BUILD FAILED, see', os.path.join(OUT, 'botrix.dll' if ok else 'build.log'))
sys.exit(0 if ok else 1)
