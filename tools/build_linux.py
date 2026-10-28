"""Build the Botrix plugin for a Linux dedicated server (i386), for one of the two Stargate Source mods.

    python3 build_linux.py ob|ep1 --src <botrix> --sdk <hl2sdk> [--out <dir>] [-j N]

  ob   Stargate: The Last Stand (Source 2007 "orangebox" engine): hl2sdk branch "orangebox"
  ep1  StargateTC 2 (Source 2006 "episode1" engine): hl2sdk branch "episode1"

Needs g++ with 32-bit support (Debian: apt install g++-multilib). Output: <out>/botrix.so, to install as
<mod>/addons/botrix_i486.so (the engine adds "_i486.so" to the path in addons/botrix.vdf).
"""
import argparse
import glob
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument('target', choices=['ob', 'ep1'])
ap.add_argument('--src', required=True)
ap.add_argument('--sdk', required=True)
ap.add_argument('--out')
ap.add_argument('-j', type=int, default=os.cpu_count() or 4)
a = ap.parse_args()
SRC = os.path.abspath(a.src)
SDK = os.path.abspath(a.sdk)
OUT = os.path.abspath(a.out or os.path.join(os.getcwd(), 'build-linux-' + a.target))
os.makedirs(OUT, exist_ok=True)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, errors='replace')


if a.target == 'ob':
    incs = ['.', 'public', 'public/engine', 'public/tier0', 'public/tier1', 'public/game/server', 'public/mathlib',
            'public/vstdlib', 'game/server', 'game/server/hl2', 'game/server/hl2mp', 'game/shared', 'common']
    defs = ['BOTRIX_SOURCE_ENGINE_2007', 'BOTRIX_TF2', 'BOTRIX_SGTLS']
    mod_dirs = ['sgtls']
    extra_files = ['mods/tf2/bot_tf2.cpp', 'mods/tf2/mod_tf2.cpp']
    lib = os.path.join(SDK, 'lib/linux')
else:
    # StargateTC 2 shares the SGTLS helpers; the crash logger (Windows only) compiles to nothing.
    incs = ['.', 'public', 'public/engine', 'public/tier0', 'public/tier1', 'public/dlls', 'public/mathlib',
            'public/vstdlib', 'dlls', 'dlls/hl2_dll', 'dlls/hl2mp_dll', 'game_shared', 'game_shared/hl2mp']
    defs = ['BOTRIX_SOURCE_ENGINE_2006', 'BOTRIX_NO_COMMAND_COMPLETION', 'BOTRIX_SGTC2']
    mod_dirs = ['sgtc2']
    extra_files = ['mods/sgtls/crash_handler.cpp', 'mods/sgtls/sgtls_util.cpp', 'mods/sgtls/sgtls_map.cpp',
                   'mods/sgtls/objectives_sgtls.cpp', 'mods/sgtls/linux_server.cpp']
    lib = os.path.join(SDK, 'linux_sdk')
defs += ['BOTRIX_HL2DM', 'BOTRIX_BOT_AIM_ERROR', 'GOOD_INI_ONE_KV_SEPARATOR', 'GOOD_INI_ONE_COMMENT_CHAR',
         'GOOD_LOG_FLUSH', 'GOOD_LOG_USE_ENDL', 'VECTOR', 'GAME_DLL', 'HL2_DLL', 'HL2_MP', 'HL2_EPISODIC', 'MP_SDK',
         'VPC', 'NDEBUG', 'NO_MALLOC_OVERRIDE']
# What the SDK's linux_sdk/Makefile defines.
defs += ['_LINUX', 'LINUX', 'POSIX', 'GNUC', 'COMPILER_GCC', 'VPROF_LEVEL=1', 'SWDS', '_finite=finite',
         'stricmp=strcasecmp', '_stricmp=strcasecmp', '_strnicmp=strncasecmp', 'strnicmp=strncasecmp',
         '_vsnprintf=vsnprintf', '_alloca=alloca', 'strcmpi=strcasecmp']
files = ['good/src/file.cpp', 'good/src/ini_file.cpp', 'good/src/log.cpp', 'good/src/mutex.cpp', 'good/src/process.cpp',
         'good/src/thread.cpp', 'bot.cpp', 'chat.cpp', 'clients.cpp', 'config.cpp', 'console_commands.cpp', 'event.cpp',
         'item.cpp', 'mod.cpp', 'players.cpp', 'server_plugin.cpp', 'source_engine.cpp', 'type2string.cpp',
         'waypoint.cpp', 'waypoint_navigator.cpp', 'weapon.cpp', 'mods/hl2dm/bot_hl2dm.cpp', 'mods/hl2dm/mod_hl2dm.cpp']
files += extra_files
for d in mod_dirs:
    files += sorted(os.path.relpath(f, SRC) for f in glob.glob(os.path.join(SRC, 'mods', d, '*.cpp')))
files = list(dict.fromkeys(files))

cxx = ['g++', '-m32', '-march=pentium4', '-mfpmath=sse', '-fPIC', '-O2', '-g', '-std=gnu++14', '-fpermissive',
       '-fno-strict-aliasing', '-fvisibility=hidden', '-fno-exceptions', '-w', '-Usprintf', '-Ustrncpy',
       '-UPROTECTED_THINGS_ENABLE', '-ffile-prefix-map=' + SRC + '/=', '-ffile-prefix-map=' + SDK + '/=hl2sdk/']
cxx += ['-I' + SRC, '-I' + SRC + '/good/include'] + ['-I' + os.path.join(SDK, i) for i in incs]
cxx += ['-D' + d for d in defs]


def obj_of(f):
    return os.path.join(OUT, f.replace('/', '__')[:-4] + '.o')


def compile_one(f):
    r = run(cxx + ['-c', os.path.join(SRC, f), '-o', obj_of(f)])
    return f, r.returncode, r.stdout + r.stderr


log = []
fails = 0
with ThreadPoolExecutor(a.j) as ex:
    for f, rc, out in ex.map(compile_one, files):
        log.append(f'== {f} rc={rc}\n{out}')
        fails += rc != 0
built = False
if not fails:
    # Our own libstdc++ (static, before tier0_i486.so, which exports an old one), not exported. tier1 stays
    # exported (CreateInterface comes from it); -Bsymbolic binds our references to its globals (g_pCVar...) to our
    # copies, not the engine's.
    def gcc_file(name):
        return run(['g++', '-m32', '-print-file-name=' + name]).stdout.strip()

    r = run(['g++', '-m32', '-shared', '-o', os.path.join(OUT, 'botrix.so')] + [obj_of(f) for f in files] +
            [lib + '/tier1_i486.a', lib + '/mathlib_i486.a', gcc_file('libstdc++.a'), gcc_file('libsupc++.a'),
             gcc_file('libgcc_eh.a'), '-L' + lib, '-l:tier0_i486.so', '-l:vstdlib_i486.so', '-static-libgcc',
             '-static-libstdc++', '-ldl', '-lpthread', '-Wl,--no-undefined',
             '-Wl,--exclude-libs,libstdc++.a:libsupc++.a:libgcc_eh.a:libgcc.a:mathlib_i486.a', '-Wl,-Bsymbolic'])
    log.append('== link rc=%d\n%s%s' % (r.returncode, r.stdout, r.stderr))
    built = r.returncode == 0
text = '\n'.join(log)
open(os.path.join(OUT, 'build.log'), 'w').write(text)
errs = [l for l in text.splitlines() if 'error' in l.lower() or 'undefined reference' in l]
for l in list(dict.fromkeys(errs))[:60]:
    print(l[:300])
print('BUILD OK: ' + os.path.join(OUT, 'botrix.so') if built else 'BUILD FAILED, see ' + os.path.join(OUT, 'build.log'))
sys.exit(0 if built else 1)
