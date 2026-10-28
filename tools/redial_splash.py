"""Stamp "REDIAL V<version>" on the menu / loading backgrounds of the Source mods (Stargate: The Last Stand,
StargateTC 2), as was done for StargateTC (tools/stamp_splash.py of the Redial release).

The background is materials/console/background01[_widescreen].vtf (VTF 7.2, DXT1). The script decodes the top
mip, draws the text (Perpetua Titling, white with a soft blue glow, like the titles of the art), and writes the
texture back UNCOMPRESSED (BGR888, format 3; sgtls already ships console/background02.vtf that way): same header
(only the format changes), same low-res thumbnail, mips rebuilt from the stamped image. The text is pre-squeezed or
pre-widened so that it keeps its proportions once the texture is stretched to the screen.

  py -I redial_splash.py <sourcemods dir> <out dir> [version]
Reads the mods' original textures (DXT1) from <sourcemods dir>/<mod>/materials/console; a mod that isn't installed is
skipped. Writes <out>/<mod>/materials/console/*.vtf (to copy over the mod's files) and <out>/preview_*.png (as
displayed). Needs Pillow and Windows' Perpetua Titling fonts.
"""
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_BOLD = r'C:\Windows\Fonts\PERTIBD.TTF'
FONT_LIGHT = r'C:\Windows\Fonts\PERTILI.TTF'

# (mod, texture, screen aspect it is shown at, text anchor (right x, baseline y) in texture pixels, cap height px,
#  font, tracking in em)
TARGETS = [
    ('stargatetc2', 'background01.vtf', 16 / 9, (1828, 410), 44, FONT_BOLD, 0.30),
    ('sgtls', 'background01.vtf', 4 / 3, (990, 990), 30, FONT_LIGHT, 0.32),
    ('sgtls', 'background01_widescreen.vtf', 16 / 9, (2010, 990), 30, FONT_LIGHT, 0.32),
]


def read_vtf(path):
    d = open(path, 'rb').read()
    sig, v1, v2, hs, w, h, flags, frames = struct.unpack_from('<4sIIIHHIH', d, 0)
    fmt, mips, lr_fmt, lr_w, lr_h = struct.unpack_from('<iBiBB', d, 52)
    if sig != b'VTF\0' or (v1, v2) != (7, 2) or hs != 80 or frames != 1 or fmt != 13 or lr_fmt != 13:
        raise ValueError(f'{path}: expected a single-frame VTF 7.2 DXT1 texture')
    lr_size = max(1, (lr_w + 3) // 4) * max(1, (lr_h + 3) // 4) * 8
    top = max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 8
    img = Image.frombytes('RGBA', (w, h), d[len(d) - top:], 'bcn', 1).convert('RGB')
    return d[:80], d[80:80 + lr_size], w, h, mips, img


def write_vtf(path, header, lowres, w, h, mips, img):
    head = bytearray(header)
    struct.pack_into('<i', head, 52, 3)                    # IMAGE_FORMAT_BGR888
    levels = []
    for i in range(mips):                                   # largest first; stored smallest first
        mw, mh = max(1, w >> i), max(1, h >> i)
        levels.append((img if i == 0 else img.resize((mw, mh), Image.LANCZOS)).tobytes('raw', 'BGR'))
    with open(path, 'wb') as f:
        f.write(head)
        f.write(lowres)
        for data in reversed(levels):
            f.write(data)
    # check: the file reads back as the stamped picture
    d = open(path, 'rb').read()
    assert len(d) == 80 + len(lowres) + sum(len(x) for x in levels)
    assert d[len(d) - len(levels[0]):] == levels[0]


def text_image(text, cap, font_path, tracking, xscale):
    """White text with a blue glow on transparent, letters spaced like the art's titles."""
    size = int(cap / 0.68)                                  # Perpetua Titling: cap height ~0.68 em
    font = ImageFont.truetype(font_path, size)
    pad = int(cap * 0.8)
    widths = [font.getlength(c) for c in text]
    step = [w + (tracking * size if c != ' ' else tracking * size * 0.5) for c, w in zip(text, widths)]
    tw = int(sum(step) - tracking * size) + 2 * pad
    th = size + 2 * pad
    mask = Image.new('L', (tw, th), 0)
    dr = ImageDraw.Draw(mask)
    x = pad
    for c, s in zip(text, step):
        dr.text((x, pad), c, font=font, fill=255)
        x += s
    mask = mask.crop((0, 0, tw, th))
    if xscale != 1:
        mask = mask.resize((max(1, int(tw * xscale)), th), Image.LANCZOS)
    glow = mask.filter(ImageFilter.GaussianBlur(cap * 0.18)).point(lambda v: min(255, int(v * 1.6)))
    out = Image.new('RGBA', mask.size, (0, 0, 0, 0))
    out.paste((120, 160, 235, 255), (0, 0), glow.point(lambda v: int(v * 0.8)))
    out.paste((236, 242, 255, 255), (0, 0), mask)
    return out, pad, font.getbbox('H')[3]


def main():
    src, out = sys.argv[1], sys.argv[2]
    version = sys.argv[3] if len(sys.argv) > 3 else '1.0.0'
    text = 'REDIAL V' + version
    for mod, name, aspect, (right, base), cap, font_path, tracking in TARGETS:
        path = os.path.join(src, mod, 'materials', 'console', name)
        if not os.path.exists(path):
            print(f'{mod}/{name}: not installed, skipped')
            continue
        header, lowres, w, h, mips, img = read_vtf(path)
        # Stretch factor of the texture on screen (screen aspect / texture aspect): draw 1/factor as wide.
        xscale = 1 / (aspect / (w / h))
        stamp, pad, baseline = text_image(text, cap, font_path, tracking, xscale)
        x = int(right - (stamp.width - pad * xscale))
        y = int(base - baseline - pad)
        img = img.convert('RGBA')
        img.alpha_composite(stamp, (x, y))
        img = img.convert('RGB')
        dst = os.path.join(out, mod, 'materials', 'console', name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        write_vtf(dst, header, lowres, w, h, mips, img)
        shown = img.resize((int(1080 * aspect), 1080), Image.LANCZOS)
        prev = os.path.join(out, f'preview_{mod}_{name[:-4]}.png')
        shown.save(prev)
        print(f'{mod}/{name}: {w}x{h}, {mips} mips -> {os.path.getsize(dst)} bytes; text at ({x},{y}); preview {prev}')


main()
