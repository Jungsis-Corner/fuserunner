#!/usr/bin/env python3
"""Loading screen for FUSE RUNNER (Sinclair QL Mode 8, 256x256, 8 colours).

Writes
  fuse_scr      raw 32K QL screen (LBYTES ...,131072 in the BOOT file)
  splash.inc    the same screen RLE-packed for the game itself
  splash.png    preview (pixels doubled in width like on the QL)
RLE: control byte c < 128: copy c+1 literal bytes; c >= 128: repeat the
next byte c-125 times (3..130); 0 bytes is not used; end marker: none,
the unpacker stops after 32768 bytes.
"""
import math
import random
from PIL import Image

K, B, R, M, G, C, Y, W = range(8)
PAL = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0),
       (0, 255, 255), (255, 255, 0), (255, 255, 255)]
img = [[K] * 256 for _ in range(256)]


def px(x, y, c):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < 256 and 0 <= y < 256:
        img[y][x] = c


def dpx(x, y, c, mode):
    """pattern pixel: 'check', 'dots', 'dots8'"""
    x, y = int(round(x)), int(round(y))
    if mode == 'check' and (x + y) & 1:
        return
    if mode == 'dots' and (x & 1 or y & 1):
        return
    if mode == 'dots8' and (x & 3 or y & 1):
        return
    px(x, y, c)


def rect(x, y, w, h, c, mode=None):
    for yy in range(int(y), int(y + h)):
        for xx in range(int(x), int(x + w)):
            if mode:
                dpx(xx, yy, c, mode)
            else:
                px(xx, yy, c)


def ellipse(cx, cy, ry, c, rx=None, mode=None):
    rx = ry * 0.75 if rx is None else rx
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                dpx(x, y, c, mode) if mode else px(x, y, c)


def line(x0, y0, x1, y1, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n + 1):
        t = i / n
        px(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c)


# ------------------------------------------------------------------ font
FONT = {
    'F': ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    'U': ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    'S': [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    'E': ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    'R': ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    'N': ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
    'I': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    'C': [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
    'L': ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    'A': [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    'Q': [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    'J': ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
    'G': [".####", "#....", "#....", "#.###", "#...#", "#...#", ".####"],
    'O': [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    'D': ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    'W': ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    'T': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    '.': [".....", ".....", ".....", ".....", ".....", ".....", "..#.."],
    '2': [".###.", "#...#", "....#", "..##.", ".#...", "#....", "#####"],
    '0': [".###.", "#..##", "#.#.#", "#.#.#", "#.#.#", "##..#", ".###."],
    '6': ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    '8': [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    '(': ["..#..", ".#...", "#....", "#....", "#....", ".#...", "..#.."],
    ')': ["..#..", "...#.", "....#", "....#", "....#", "...#.", "..#.."],
    ' ': ["....."] * 7,
}


def text(s, x, y, sx, sy, colour_of_row, shadow=None, gap=1, outline=K):
    """colour_of_row(r) -> colour or (c1, c2) checker mix, r = pixel row."""
    cells = []
    for i, ch in enumerate(s):
        g = FONT[ch]
        ox = x + i * (5 + gap) * sx
        for r in range(7):
            for c in range(5):
                if g[r][c] == '#':
                    cells.append((ox + c * sx, y + r * sy, r))
    if shadow is not None:
        for cx, cy, r in cells:
            rect(cx + 2, cy + 2, sx, sy, shadow)
    if outline is not None:
        for cx, cy, r in cells:
            rect(cx - 1, cy - 1, sx + 2, sy + 2, outline)
    for cx, cy, r in cells:
        for yy in range(sy):
            col = colour_of_row(r * sy + yy)
            for xx in range(sx):
                if isinstance(col, tuple):
                    c = col[(cx + xx + cy + yy) & 1]
                else:
                    c = col
                px(cx + xx, cy + yy, c)


def text_width(s, sx, gap=1):
    return len(s) * (5 + gap) * sx - gap * sx


# ------------------------------------------------------------------ sprites (from gfx.py)
import gfx
COL = gfx.COL


def big_sprite(rows, x, y, sx, sy):
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch != '.':
                rect(x + c * sx, y + r * sy, sx, sy, COL[ch])


# ================================================================== picture
rnd = random.Random(42)
for _ in range(120):
    x, y = rnd.randrange(256), rnd.randrange(0, 180)
    px(x, y, W if rnd.random() < 0.6 else C)
rect(0, 196, 256, 36, M, 'dots8')
# moon
ellipse(226, 30, 18, Y)
ellipse(220, 26, 3, W, mode='check')
ellipse(232, 36, 2, W, mode='check')
# light rays behind the logo
for a in range(0, 360, 10):
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    for t in range(56, 104):
        xx = 128 + ca * t * 0.95
        yy = 50 + sa * t * 0.5
        dpx(xx, yy, Y if t < 74 else R, 'check')

# city skyline
x = 0
while x < 256:
    w = rnd.randint(10, 22)
    h = rnd.randint(26, 62)
    rect(x, 232 - h, w, h, B)
    rect(x, 232 - h, w, 1, C)
    for yy in range(232 - h + 4, 228, 6):
        for xx in range(x + 2, x + w - 2, 4):
            if rnd.random() < 0.45:
                rect(xx, yy, 2, 3, Y if rnd.random() < 0.3 else M)
    x += w + rnd.randint(1, 4)
# brick floor
for y in range(232, 256):
    for x in range(256):
        r = (y - 232) % 6
        c = R
        if r == 0:
            c = Y if y == 232 else M
        elif ((x + (4 if (y - 232) // 6 % 2 else 0)) % 8) == 0:
            c = K
        px(x, y, c)
rect(0, 241, 256, 11, K)


def grad1(r):            # FUSE: white top, yellow, yellow/red mix, red
    if r < 5:
        return W
    if r < 16:
        return Y
    return R


def grad2(r):            # RUNNER: white, cyan, cyan/blue mix, magenta
    if r < 4:
        return W
    if r < 14:
        return C
    return M


wd = text_width("FUSE", 5)
text("FUSE", 128 - wd // 2, 10, 5, 5, grad1, shadow=M, outline=None)
wd = text_width("RUNNER", 4)
text("RUNNER", 128 - wd // 2, 52, 4, 4, grad2, shadow=B, outline=None)
wd = text_width("SINCLAIR QL", 2)
text("SINCLAIR QL", 128 - wd // 2, 88, 2, 2, lambda r: (C if r < 7 else W), outline=None)

# hero, bombs, enemies
big_sprite(gfx.JACK['glide'], 18, 116, 4, 4)
for (bx, by, lit) in [(104, 150, True), (132, 118, False), (170, 146, False), (76, 116, False)]:
    big_sprite(gfx.BOMB_L1 if lit else gfx.BOMB_N, bx, by, 3, 3)
for i in range(8):                       # sparks of the lit bomb
    px(124 + i * 3, 146 - i * 3, Y if i % 2 else W)
    px(125 + i * 3, 147 - i * 3, R)
big_sprite(gfx.WALKER[0], 202, 186, 3, 3)
big_sprite(gfx.SEEKER[1], 206, 112, 3, 3)
big_sprite(gfx.HOPPER[1], 160, 176, 2, 3)

wd = text_width("(C) 2026 JUNGSI", 1)
text("(C) 2026 JUNGSI", 128 - wd // 2, 243, 1, 1, lambda r: W, outline=None)


# ================================================================== output
def ql_screen():
    data = bytearray(32768)
    for y in range(256):
        for xw in range(64):
            w = 0
            for p in range(4):
                c = img[y][xw * 4 + p]
                w |= gfx.pixbits(c, p)
            o = y * 128 + xw * 2
            data[o] = w >> 8
            data[o + 1] = w & 0xff
    return bytes(data)


def rle(data):
    out = bytearray()
    i, n = 0, len(data)
    lit = bytearray()

    def flush():
        nonlocal lit
        while lit:
            chunk = lit[:128]
            out.append(len(chunk) - 1)
            out.extend(chunk)
            lit = lit[128:]
    while i < n:
        j = i
        while j < n and data[j] == data[i] and j - i < 130:
            j += 1
        if j - i >= 3:
            flush()
            out.append(j - i + 125)
            out.append(data[i])
            i = j
        else:
            lit.append(data[i])
            i += 1
    flush()
    return bytes(out)


def unrle(packed):
    out = bytearray()
    i = 0
    while len(out) < 32768:
        c = packed[i]; i += 1
        if c < 128:
            out.extend(packed[i:i + c + 1]); i += c + 1
        else:
            out.extend(bytes([packed[i]]) * (c - 125)); i += 1
    return bytes(out)


def main():
    scr = ql_screen()
    open("fuse_scr", "wb").write(scr)
    packed = rle(scr)
    assert unrle(packed) == scr
    with open("splash.inc", "w") as f:
        f.write(f"; generated by splash.py - RLE packed loading screen ({len(packed)} bytes)\n")
        f.write("splash:\n")
        for i in range(0, len(packed), 16):
            f.write("        dc.b    " + ",".join(map(str, packed[i:i + 16])) + "\n")
        f.write("        even\n")
    im = Image.new('RGB', (512, 256))
    p = im.load()
    for y in range(256):
        for x in range(256):
            p[2 * x, y] = p[2 * x + 1, y] = PAL[img[y][x]]
    im.save("splash.png")
    print("packed", len(packed), "bytes")


if __name__ == "__main__":
    main()
