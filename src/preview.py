#!/usr/bin/env python3
"""Preview backdrops (and levels if levels.py exists) as PNG, QL Mode 8 look."""
import sys
from PIL import Image
import backdrops as bdm
PAL = [(0,0,0),(0,0,255),(255,0,0),(255,0,255),(0,255,0),(0,255,255),(255,255,0),(255,255,255)]

def render(name, fn, level=None):
    img = fn().render()
    im = Image.new('RGB', (512, 256))
    pxl = im.load()
    def put(x, y, c):
        pxl[2*x, y] = PAL[c]; pxl[2*x+1, y] = PAL[c]
    for y in range(256):
        for x in range(256):
            c = img[y][x]
            if c is not None:
                put(x, y, c)
    if level:
        for (x, y, w, h) in level['plats']:
            for yy in range(y, y+h):
                for xx in range(x, x+w):
                    put(xx, yy, 6 if yy == y else 2)
        for (x, y) in level['bombs']:
            for yy in range(y+2, y+8):
                for xx in range(x+1, x+7):
                    put(xx, yy, 2)
            put(x+5, y, 6); put(x+4, y+1, 7)
        jx, jy = level['start']
        for yy in range(jy, jy+16):
            for xx in range(jx+2, jx+10):
                put(xx, yy, 5)
    for x in range(256):
        for y in range(16, 20): put(x, y, 2)
    for y in range(20, 256):
        for x in list(range(0, 4)) + list(range(252, 256)): put(x, y, 2)
    return im

if __name__ == '__main__':
    lv = {}
    try:
        import levels
        lv = {l['bg']: l for l in levels.LEVELS}
    except ImportError:
        pass
    ims = [render(n, f, lv.get(n)) for n, f in bdm.BACKDROPS]
    sheet = Image.new('RGB', (1024, 256 * ((len(ims) + 1) // 2)))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % 2) * 512, (i // 2) * 256))
    sheet.save(sys.argv[1] if len(sys.argv) > 1 else 'shots/preview.png')
