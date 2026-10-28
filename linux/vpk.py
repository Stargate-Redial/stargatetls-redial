"""Minimal VPK v1/v2 reader (Valve pack files), standard library only.

  py -I vpk.py stats  <x_dir.vpk> [...]            sizes by top dir / extension
  py -I vpk.py list   <x_dir.vpk>                   one line per file: size path
  py -I vpk.py extract <outdir> <filter> <x_dir.vpk> [...]
        filter: 'server' (what a dedicated server reads) or 'all'
        Files that already exist with the same size are skipped; earlier VPKs
        on the command line win over later ones (pass them in search order).
"""
import os
import struct
import sys
import collections

SIG = 0x55AA1234


def _cstr(buf, pos):
    end = buf.index(b'\0', pos)
    return buf[pos:end].decode('latin1'), end + 1


def read_dir(path):
    with open(path, 'rb') as f:
        head = f.read(28)
        sig, ver, tree_size = struct.unpack_from('<III', head)
        if sig != SIG or ver not in (1, 2):
            raise ValueError(f'{path}: not a VPK v1/v2 (sig {sig:#x} ver {ver})')
        hsize = 12 if ver == 1 else 28
        f.seek(hsize)
        tree = f.read(tree_size)
    data_base = hsize + tree_size
    entries = []
    pos = 0
    while True:
        ext, pos = _cstr(tree, pos)
        if not ext:
            break
        while True:
            d, pos = _cstr(tree, pos)
            if not d:
                break
            while True:
                name, pos = _cstr(tree, pos)
                if not name:
                    break
                crc, preload, arch, off, length, term = struct.unpack_from('<IHHIIH', tree, pos)
                pos += 18
                if term != 0xFFFF:
                    raise ValueError(f'{path}: bad entry terminator at {pos}')
                pre_off = pos
                pos += preload
                rel = name if ext == ' ' else f'{name}.{ext}'
                if d != ' ':
                    rel = f'{d}/{rel}'
                entries.append((rel.lower(), crc, preload, pre_off, arch, off, length))
    return path, data_base, tree, entries


# What a dedicated server needs: no textures (.vtf), no client-only data.
SERVER_SKIP_EXT = {'vtf', 'vcs', 'dx80.vtx', 'dx90.vtx', 'sw.vtx', 'xbox.vtx', 'vtx',
                   'bik', 'avi', 'ttf', 'res', 'cur', 'ani_', 'tga', 'jpg', 'png', 'psd', 'html'}
# HL2 voice-overs and music are only played on clients (600 + 66 MB).
SERVER_SKIP_DIRS = ('materials/vgui/', 'materials/console/', 'resource/ui/', 'media/', 'shaders/',
                    'sound/vo/', 'sound/music/')


def wanted(rel, filt):
    if filt == 'all':
        return True
    low = rel.lower()
    # Paths start with the game dir (hl2/, sourcetest/, ...).
    if low.split('/', 1)[-1].startswith(SERVER_SKIP_DIRS):
        return False
    base = low.rsplit('/', 1)[-1]
    parts = base.split('.')
    if len(parts) >= 3:
        ext2 = '.'.join(parts[-2:])
        if ext2 == 'dx90.vtx':      # the dedicated server's MDLCache loads it
            return True
        if ext2 in SERVER_SKIP_EXT:
            return False
    return parts[-1] not in SERVER_SKIP_EXT


def file_size(e):
    return e[2] + e[6]


def stats(paths, filt='all'):
    by_top = collections.Counter()
    by_ext = collections.Counter()
    total = 0
    count = 0
    for p in paths:
        _, _, _, entries = read_dir(p)
        for e in entries:
            if not wanted(e[0], filt):
                continue
            s = file_size(e)
            total += s
            count += 1
            by_top[e[0].split('/', 1)[0]] += s
            by_ext[e[0].rsplit('.', 1)[-1] if '.' in e[0].rsplit('/', 1)[-1] else ''] += s
    print(f'{count} files, {total / 1e6:.1f} MB ({filt})')
    for k, v in by_top.most_common(15):
        print(f'  dir {k:20s} {v / 1e6:9.1f} MB')
    for k, v in by_ext.most_common(15):
        print(f'  ext {k:20s} {v / 1e6:9.1f} MB')


def extract(outdir, filt, paths):
    done = set()
    written = skipped = 0
    for p in paths:
        dirpath, data_base, tree, entries = read_dir(p)
        stem = dirpath[:-len('_dir.vpk')]
        handles = {}
        try:
            for rel, crc, preload, pre_off, arch, off, length in entries:
                if rel in done or not wanted(rel, filt):
                    continue
                done.add(rel)
                dst = os.path.join(outdir, *rel.split('/'))
                size = preload + length
                if os.path.exists(dst) and os.path.getsize(dst) == size:
                    skipped += 1
                    continue
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                data = tree[pre_off:pre_off + preload]
                if length:
                    if arch == 0x7FFF:
                        key, fpath, base = 'dir', dirpath, data_base
                    else:
                        key, fpath, base = arch, f'{stem}_{arch:03d}.vpk', 0
                    h = handles.get(key)
                    if h is None:
                        h = handles[key] = open(fpath, 'rb')
                    h.seek(base + off)
                    data += h.read(length)
                if len(data) != size:
                    raise IOError(f'{rel}: short read ({len(data)}/{size})')
                with open(dst + '.part', 'wb') as o:
                    o.write(data)
                os.replace(dst + '.part', dst)
                written += 1
        finally:
            for h in handles.values():
                h.close()
    print(f'extracted {written}, already present {skipped}, into {outdir}')


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'stats':
        filt = 'all'
        args = sys.argv[2:]
        if args and args[0] in ('server', 'all'):
            filt, args = args[0], args[1:]
        stats(args, filt)
    elif cmd == 'list':
        for e in read_dir(sys.argv[2])[3]:
            print(file_size(e), e[0])
    elif cmd == 'extract':
        extract(sys.argv[2], sys.argv[3], sys.argv[4:])
    else:
        sys.exit(__doc__)
