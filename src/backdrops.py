#!/usr/bin/env python3
"""Backdrop generator for FUSE RUNNER (Sinclair QL, Mode 8).

Each backdrop is painted in layers. Every layer is flattened to run-length
spans and written to bgdata.inc as: y, x0, length, colour|pattern<<3.
The QL draws the spans in order, so later layers cover earlier ones.
Pattern modes (only pixels that match the pattern are set, the rest of the
span stays transparent):
  0 solid            1 checker 50%        2 dots 25%          3 h-lines
  4 window grid      5 brick/stone lines  6 v-lines           7 dots 12.5%
y = 255 ends a list. Mode 8 pixels are about twice as wide as tall, so
circles use a 0.75 x radius.
"""
import math
import random

K, B, R, M, G, C, Y, W = range(8)
SOLID, CHECK, DOTS, HLINE, WIN, BRICK, VLINE, DOTS8 = range(8)
XL, XR = 4, 252               # usable x range (walls outside)
YT, YB = 20, 248              # below ceiling, above floor


def pat(mode, x, y):
    """must match pattern test in fuse.asm (draw_spans)"""
    if mode == SOLID:
        return True
    if mode == CHECK:
        return (x + y) & 1 == 0
    if mode == DOTS:
        return x & 1 == 0 and y & 1 == 0
    if mode == HLINE:
        return y & 1 == 0
    if mode == WIN:
        return (x & 3) in (1, 2) and (y & 7) in (2, 3, 4)
    if mode == BRICK:
        return (y & 3) == 0 or ((x + ((y >> 2) & 1) * 4) & 7) == 0
    if mode == VLINE:
        return x & 1 == 0
    if mode == DOTS8:
        return x & 3 == 0 and y & 1 == 0


def P(c, mode=SOLID):
    return c | (mode << 3)


class Backdrop:
    """Records drawing operations; emitted as compact byte code:
       y<248 : hspan  y, x0, len, col
       248   : PROFILE x0, n, col, ybottom, n*ytop   (fill columns down)
       249   : EDGE    x0, n, col, n*y               (one pixel per column)
       250   : RECT    x, y, w, h, col
       251   : COLS    x0, n, col, n*(ytop, len)     (vertical runs)
       255   : end
    """
    def __init__(self):
        self.ops = []

    def layer(self):
        pass                                     # kept for readability

    # ---- primitives (c = colour | pattern<<3) ----
    def _clipx(self, x0, x1):
        return max(int(round(x0)), XL), min(int(round(x1)), XR - 1)

    def hline(self, x0, x1, y, c):
        y = int(round(y))
        x0, x1 = self._clipx(x0, x1)
        if YT <= y < YB and x1 >= x0:
            self.ops.append(('h', y, x0, x1 - x0 + 1, c))

    def px(self, x, y, c):
        self.hline(x, x, y, c)

    def rect(self, x, y, w, h, c):
        x, y, w, h = int(x), int(y), int(w), int(h)
        x0, x1 = self._clipx(x, x + w - 1)
        y0, y1 = max(y, YT), min(y + h - 1, YB - 1)
        if x1 < x0 or y1 < y0:
            return
        if y1 == y0:
            self.hline(x0, x1, y0, c)
        else:
            self.ops.append(('r', x0, y0, x1 - x0 + 1, y1 - y0 + 1, c))

    def vline(self, x, y0, y1, c):
        self.rect(x, int(y0), 1, int(y1) - int(y0) + 1, c)

    def band(self, y0, y1, c):
        self.rect(XL, y0, XR - XL, y1 - y0, c)

    def profile(self, f, c, y1=YB - 1, edge=None, x0=XL, x1=XR):
        tops = [max(YT, min(y1, int(round(f(x))))) for x in range(x0, x1)]
        self.ops.append(('p', x0, c, y1, tops))
        if edge is not None:
            self.ops.append(('e', x0, edge, tops))

    def cols(self, x0, runs, c):
        """runs: list of (ytop, length) per column starting at x0"""
        while runs and x0 < XL:
            x0 += 1
            runs = runs[1:]
        runs = runs[:max(0, XR - x0)]
        if not runs:
            return
        rr = []
        for yt, n in runs:
            yt = int(round(yt)); n = int(round(n))
            if yt < YT:
                n -= YT - yt; yt = YT
            n = max(0, min(n, YB - yt))
            rr.append((yt, n))
        self.ops.append(('c', x0, c, rr))

    def ellipse(self, cx, cy, ry, c, rx=None):
        rx = ry * 0.75 if rx is None else rx
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            xs = [x for x in range(int(cx - rx) - 1, int(cx + rx) + 2)
                  if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0]
            if xs:
                self.hline(xs[0], xs[-1], y, c)

    def tri(self, cx, top, bottom, slope, c):
        for y in range(int(top), int(bottom) + 1):
            hw = (y - top) * slope
            self.hline(cx - hw, cx + hw, y, c)

    def line(self, x0, y0, x1, y1, c):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        pts = []
        for i in range(n + 1):
            t = i / n
            pt = (int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t)))
            if not pts or pts[-1] != pt:
                pts.append(pt)
        # merge horizontal neighbours into spans
        i = 0
        while i < len(pts):
            j = i
            while j + 1 < len(pts) and pts[j + 1][1] == pts[i][1] and pts[j + 1][0] == pts[j][0] + 1:
                j += 1
            self.hline(pts[i][0], pts[j][0], pts[i][1], c)
            i = j + 1

    def poly(self, pts, c):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            n = len(pts)
            for i in range(n):
                (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                self.hline(math.ceil(xs[i]), math.floor(xs[i + 1]), y, c)

    # ---- output ----
    def bytecode(self):
        out = []
        for op in self.ops:
            k = op[0]
            if k == 'h':
                _, y, x0, n, c = op
                out += [y, x0, n, c]
            elif k == 'r':
                _, x, y, w, h, c = op
                out += [250, x, y, w, h, c]
            elif k == 'p':
                _, x0, c, y1, tops = op
                out += [248, x0, len(tops), c, y1] + tops
            elif k == 'e':
                _, x0, c, tops = op
                out += [249, x0, len(tops), c] + tops
            elif k == 'c':
                _, x0, c, rr = op
                out += [251, x0, len(rr), c]
                for yt, n in rr:
                    out += [yt, n]
        out.append(255)
        return out

    def render(self):
        """preview: 256x256 colour indices (None = untouched)"""
        img = [[None] * 256 for _ in range(256)]
        def put(x, y, c):
            if pat(c >> 3, x, y):
                img[y][x] = c & 7
        for op in self.ops:
            k = op[0]
            if k == 'h':
                _, y, x0, n, c = op
                for x in range(x0, x0 + n):
                    put(x, y, c)
            elif k == 'r':
                _, x, y, w, h, c = op
                for yy in range(y, y + h):
                    for xx in range(x, x + w):
                        put(xx, yy, c)
            elif k == 'p':
                _, x0, c, y1, tops = op
                for i, t in enumerate(tops):
                    for yy in range(t, y1 + 1):
                        put(x0 + i, yy, c)
            elif k == 'e':
                _, x0, c, tops = op
                for i, t in enumerate(tops):
                    put(x0 + i, t, c)
            elif k == 'c':
                _, x0, c, rr = op
                for i, (yt, n) in enumerate(rr):
                    for yy in range(yt, yt + n):
                        put(x0 + i, yy, c)
        return img


# ====================================================================
def pine_cols(bd, cx, base, h, col, trunk=None):
    """layered pine: one column op per layer"""
    lh = h * 0.42
    bottom = base
    for i in range(3):
        t = base - h + i * h * 0.24
        sl = 0.38 + i * 0.02
        hw = int(lh * sl)
        runs = []
        for x in range(int(cx) - hw, int(cx) + hw + 1):
            yy = t + abs(x - cx) / sl
            runs.append((yy, t + lh - yy + 1))
        bd.cols(int(cx) - hw, runs, col)
        bottom = t + lh
    if trunk is not None:
        bd.rect(cx - 1, int(bottom), 3, int(base - bottom) + 1, trunk)


def city():
    rnd = random.Random(1)
    bd = Backdrop()
    # light pollution near the horizon
    bd.band(160, 200, P(M, DOTS8))
    bd.band(200, YB, P(M, DOTS))
    # far skyline
    bd.layer()
    x = XL
    while x < XR:
        w = rnd.randint(6, 14)
        h = rnd.randint(50, 110)
        bd.rect(x, YB - h, w, h, P(B, CHECK))
        x += w + rnd.randint(0, 3)
    bd.vline(140, 92, 120, P(W))                       # radio mast
    bd.px(140, 91, P(R))
    # near buildings
    bd.layer()
    blds = [(8, 22, 64), (32, 16, 96), (50, 24, 50), (76, 16, 116), (94, 22, 74),
            (118, 18, 100), (138, 26, 56), (166, 16, 124), (184, 22, 70),
            (208, 16, 88), (226, 26, 60)]
    for bx, bw, bh in blds:
        top = YB - bh
        bd.rect(bx, top, bw, bh, P(B))
        bd.hline(bx, bx + bw - 1, top, P(C))             # roof edge
    bd.rect(80, YB - 128, 8, 12, P(B))                 # setback tower
    bd.vline(84, YB - 144, YB - 128, P(W))
    bd.px(84, YB - 145, P(R))
    bd.rect(170, YB - 132, 8, 8, P(B))
    bd.vline(174, YB - 150, YB - 132, P(W))
    bd.px(174, YB - 151, P(R))
    bd.rect(212, YB - 96, 8, 6, P(M))                  # water tank
    bd.vline(213, YB - 90, YB - 88, P(M))
    bd.vline(218, YB - 90, YB - 88, P(M))
    # windows
    bd.layer()
    for i, (bx, bw, bh) in enumerate(blds):
        col = Y if i in (1, 5, 7) else M
        for yy in range(YB - bh + 4, YB - 6):
            bd.hline(bx + 2, bx + bw - 3, yy, P(col, WIN))
    # neon sign
    bd.rect(140, 206, 22, 7, P(K))
    bd.hline(141, 160, 206, P(C))
    bd.hline(141, 160, 212, P(C))
    bd.rect(144, 208, 14, 3, P(R, VLINE))
    # street lamps
    for lx in (26, 112, 200):
        bd.vline(lx, 228, 247, P(W))
        bd.hline(lx, lx + 3, 228, P(W))
        bd.rect(lx + 3, 229, 3, 2, P(Y))
        bd.rect(lx + 1, 232, 7, 6, P(Y, DOTS8))
    return bd


def mountains():
    rnd = random.Random(2)
    bd = Backdrop()
    bd.band(170, YB, P(B, DOTS8))
    # far range
    bd.layer()
    far = [128 + 14 * math.sin(x / 19.0) + 10 * math.sin(x / 7.0 + 2) + rnd.randint(-2, 2) for x in range(256)]
    bd.profile(lambda x: far[x], P(B, CHECK), edge=P(C))
    # main range with snow
    bd.layer()
    peaks = [(30, 70), (92, 108), (150, 66), (204, 100), (250, 62)]
    def h(x):
        return max(ph - abs(x - px) * (1.0 + 0.15 * math.sin(px)) for px, ph in peaks) + 1.5 * math.sin(x * 0.9)
    tops = [YB - max(1, h(x)) for x in range(XL, XR)]
    bd.profile(lambda x: tops[x - XL], P(B), edge=P(C))
    snow = [(tops[i], 8 if h(XL + i) > 64 else 0) for i in range(len(tops))]
    bd.cols(XL, snow, P(W))
    snow2 = [(tops[i] + 8, 6 if h(XL + i) > 64 else 0) for i in range(len(tops))]
    bd.cols(XL, snow2, P(W, CHECK))
    # rock shading on the right flanks of the big peaks
    for px, ph in peaks:
        if ph < 90:
            continue
        runs = []
        for x in range(px + 2, px + 34):
            t = YB - h(x) + 14
            runs.append((t, max(0, YB - 20 - t)))
        bd.cols(px + 2, runs, P(K, DOTS8))
    # near hills with pines
    bd.layer()
    near = lambda x: 222 + 6 * math.sin(x / 15.0) + 3 * math.sin(x / 5.0)
    bd.profile(near, P(G, CHECK), edge=P(G))
    for tx in (14, 40, 66, 170, 196, 236):
        base = near(tx) + 2
        pine_cols(bd, tx, base + 2, 22, P(G), P(M))
    # cabin with lit window and smoke
    bd.rect(110, 226, 20, 12, P(M))
    bd.poly([(107, 226), (120, 216), (133, 226)], P(R))
    bd.rect(114, 229, 4, 4, P(Y))
    bd.rect(123, 230, 4, 8, P(K))
    bd.rect(126, 212, 3, 8, P(M))
    for i in range(8):
        bd.ellipse(128 + i * 2.5, 206 - i * 6, 3 + i * 0.4, P(W, DOTS8))
    return bd


def desert():
    bd = Backdrop()
    bd.band(150, 172, P(R, DOTS8))                     # warm horizon glow
    bd.layer()
    for x0, w, h in [(18, 34, 40), (150, 46, 52), (206, 26, 34)]:   # mesas
        top = 182 - h
        bd.poly([(x0, 182), (x0 + 5, top), (x0 + w - 5, top), (x0 + w, 182)], P(B))
        bd.hline(x0 + 5, x0 + w - 5, top, P(C))
        bd.rect(x0 + 6, top + 6, w - 12, h - 8, P(K, DOTS8))
        bd.hline(x0 + 6, x0 + w - 7, top + 3, P(M))
    bd.layer()
    far = lambda x: 172 + 10 * math.sin(x / 23.0) + 6 * math.sin(x / 9.0 + 1)
    bd.profile(far, P(B, CHECK), edge=P(B))
    # camel caravan on the far dune
    for i, cx in enumerate((92, 104, 116)):
        base = int(far(cx)) - 1
        bd.rect(cx - 3, base - 6, 7, 3, P(K))
        bd.px(cx, base - 7, P(K))
        bd.vline(cx + 4, base - 9, base - 5, P(K))
        bd.hline(cx + 4, cx + 5, base - 9, P(K))
        for lx in (cx - 3, cx - 1, cx + 1, cx + 3):
            bd.vline(lx, base - 3, base, P(K))
    bd.layer()
    near = lambda x: 206 + 9 * math.sin(x / 17.0 + 2) + 5 * math.sin(x / 7.0)
    bd.profile(near, P(M, CHECK), edge=P(M))
    bd.layer()
    runs = [(near(x) + 3, YB - near(x) - 3) for x in range(XL, XR)]
    bd.cols(XL, runs, P(Y, DOTS8))                      # sand sparkle
    for k in range(3):                                  # ripple lines
        tops = [int(near(x)) + 10 + k * 9 + int(2 * math.sin(x / 6.0 + k)) for x in range(XL, XR)]
        bd.ops.append(('e', XL, P(M), [min(t, YB - 1) for t in tops]))
    # saguaro cacti with highlight
    bd.layer()
    for cx, h in [(40, 44), (150, 36), (226, 50)]:
        base = int(near(cx)) + 2
        top = base - h
        bd.rect(cx - 2, top + 1, 4, h - 1, P(G))
        bd.hline(cx - 1, cx, top, P(G))
        bd.vline(cx - 1, top + 2, base - 2, P(W, CHECK))
        ay = base - int(h * 0.55)
        bd.rect(cx - 7, ay, 5, 3, P(G))
        bd.rect(cx - 7, ay - 10, 3, 10, P(G))
        bd.px(cx - 6, ay - 11, P(G))
        ay = base - int(h * 0.7)
        bd.rect(cx + 2, ay, 5, 3, P(G))
        bd.rect(cx + 4, ay - 8, 3, 8, P(G))
        bd.px(cx + 5, ay - 9, P(G))
    for x in (96, 190):
        bd.ellipse(x, int(near(x)) - 2, 3, P(Y, CHECK))
    # skull
    sx, sy = 120, int(near(120)) + 4
    bd.rect(sx, sy, 5, 3, P(W))
    bd.px(sx + 1, sy + 1, P(K))
    bd.px(sx + 3, sy + 1, P(K))
    bd.hline(sx + 1, sx + 3, sy + 3, P(W))
    return bd


def harbour():
    bd = Backdrop()
    bd.band(180, 204, P(B, DOTS8))
    bd.layer()
    bd.rect(XL, 204, XR - XL, YB - 204, P(B))           # sea
    bd.layer()
    for i, y in enumerate(range(207, 247, 4)):
        for k in range(12):
            x = (k * 23 + i * 9) % 244 + XL
            bd.hline(x, x + 4 + (i % 3), y, P(C))
    for i, y in enumerate(range(208, 246, 3)):           # moon reflection
        w = 2 + (i % 4) * 2
        bd.hline(210 - w, 210 + w, y, P(Y, CHECK))
    for x in range(118, 205):                            # ship reflection
        bd.vline(x, 213, 222, P(M, DOTS))
    # quay with stone texture
    bd.layer()
    bd.rect(XL, 192, 60, YB - 192, P(M))
    bd.layer()
    bd.rect(XL, 193, 60, YB - 193, P(K, BRICK))
    bd.hline(XL, XL + 59, 192, P(W))
    for bx in (12, 44):                                  # bollards
        bd.rect(bx, 188, 4, 4, P(Y))
    # crane
    bd.layer()
    for x in (26, 36):
        bd.vline(x, 92, 191, P(Y))
    for y in range(92, 190, 10):
        bd.line(26, y, 36, y + 10, P(Y))
        bd.line(36, y, 26, y + 10, P(Y))
    bd.rect(10, 90, 104, 2, P(Y))
    bd.line(31, 70, 10, 90, P(Y))
    bd.line(31, 70, 112, 90, P(Y))
    bd.vline(31, 70, 92, P(Y))
    bd.rect(10, 92, 10, 8, P(K))                         # counterweight
    bd.rect(10, 92, 10, 8, P(Y, HLINE))
    bd.rect(28, 100, 7, 6, P(C))                         # cabin
    bd.rect(29, 101, 5, 3, P(Y))
    bd.vline(100, 92, 150, P(W))
    bd.rect(96, 150, 9, 3, P(W))
    bd.rect(94, 153, 13, 9, P(R))
    bd.rect(94, 153, 13, 9, P(K, VLINE))
    # ship
    bd.layer()
    for y in range(194, 212):
        indent = max(0, y - 204)
        bd.hline(118 + indent, 204 - indent // 2, y, P(M))
    bd.hline(118, 204, 194, P(W))
    bd.hline(120, 202, 200, P(W))
    for x in range(124, 200, 8):
        bd.rect(x, 203, 3, 2, P(Y))                      # portholes
    bd.rect(148, 178, 40, 16, P(W))
    bd.rect(152, 170, 28, 8, P(W))
    for x in range(152, 186, 6):
        bd.rect(x, 184, 3, 3, P(Y))
    for x in range(156, 178, 6):
        bd.rect(x, 172, 3, 3, P(B))
    bd.rect(168, 156, 9, 14, P(R))
    bd.rect(168, 156, 9, 2, P(K))
    bd.hline(168, 176, 162, P(W))
    for i in range(6):
        bd.ellipse(176 + i * 4, 150 - i * 4, 2 + i * 0.5, P(W, DOTS8))
    bd.vline(132, 150, 193, P(W))
    bd.line(132, 150, 148, 178, P(W))
    bd.line(132, 150, 118, 194, P(W))
    bd.px(132, 149, P(R))
    # buoy
    bd.rect(100, 226, 5, 6, P(R))
    bd.hline(100, 104, 228, P(W))
    bd.px(102, 224, P(Y))
    # gulls
    for gx, gy in [(70, 120), (82, 112), (150, 100)]:
        bd.line(gx - 3, gy - 1, gx, gy + 1, P(W))
        bd.line(gx, gy + 1, gx + 3, gy - 1, P(W))
    # lighthouse
    bd.layer()
    bd.poly([(222, 204), (246, 204), (242, 196), (226, 196)], P(K))
    bd.rect(222, 200, 25, 4, P(W, BRICK))
    for y in range(124, 197):
        hw = 5 + (y - 124) // 20
        col = R if ((y - 124) // 12) % 2 else W
        bd.hline(234 - hw, 234 + hw, y, P(col))
    bd.rect(230, 150, 3, 5, P(Y))
    bd.rect(235, 176, 3, 5, P(Y))
    bd.rect(228, 112, 13, 12, P(K))
    bd.rect(229, 114, 11, 9, P(Y))
    bd.vline(234, 114, 122, P(W))
    bd.hline(226, 242, 124, P(W))
    bd.tri(234, 102, 111, 0.8, P(R))
    bd.layer()
    for y in range(104, 136):
        spread = (y - 104) * 0.35
        x0 = int(228 - (y - 104) * 2.2)
        if abs(y - 119) <= spread:
            bd.hline(max(x0, XL), 227, y, P(Y, DOTS))
    return bd


def castle():
    bd = Backdrop()
    bd.band(160, YB, P(B, DOTS8))
    bd.layer()
    def battlements(x0, x1, y):
        for x in range(x0, x1, 10):
            bd.rect(x, y - 6, 6, 6, P(B))
    bd.rect(56, 150, 144, YB - 150, P(B))
    battlements(56, 200, 150)
    for x0 in (36, 192):
        bd.rect(x0, 106, 28, YB - 106, P(B))
        battlements(x0, x0 + 28, 106)
    bd.rect(102, 82, 52, YB - 82, P(B))
    battlements(102, 154, 82)
    # stone texture
    bd.layer()
    bd.rect(56, 151, 144, YB - 151, P(K, BRICK))
    for x0 in (36, 192):
        bd.rect(x0, 107, 28, YB - 107, P(K, BRICK))
    bd.rect(102, 83, 52, YB - 83, P(K, BRICK))
    # windows, flag, gate
    bd.layer()
    for x0 in (36, 192):
        for wy in (122, 168):
            bd.rect(x0 + 11, wy, 5, 8, P(K))
            bd.rect(x0 + 12, wy + 1, 3, 6, P(Y))
            bd.hline(x0 + 12, x0 + 14, wy + 4, P(K))
    for x in (110, 140):
        bd.rect(x, 98, 5, 9, P(K))
        bd.rect(x + 1, 99, 3, 7, P(Y))
    bd.ellipse(128, 124, 6, P(K))
    bd.ellipse(128, 124, 4, P(Y))
    bd.vline(128, 120, 128, P(K))
    bd.hline(125, 131, 124, P(K))
    for x in (76, 92, 164, 180):
        bd.rect(x, 170, 3, 6, P(Y))
    bd.vline(128, 50, 75, P(W))
    for i in range(9):
        bd.hline(129, 129 + 14 - i * 3 // 2, 51 + i, P(M))
    for fx in (50, 206):                                # tower pennants
        bd.vline(fx, 86, 99, P(W))
        bd.poly([(51, 86), (60, 89), (51, 92)] if fx == 50 else [(207, 86), (216, 89), (207, 92)], P(R))
    bd.rect(114, 210, 28, YB - 210, P(K))
    bd.ellipse(128, 210, 11, P(K))
    for x in range(117, 140, 4):
        bd.vline(x, 202, 230, P(M))
    for y in range(204, 231, 5):
        bd.hline(117, 139, y, P(M))
    # bats
    for bx, by in [(70, 70), (84, 62), (176, 58), (230, 76)]:
        bd.line(bx - 4, by - 1, bx - 1, by + 1, P(M))
        bd.line(bx + 1, by + 1, bx + 4, by - 1, P(M))
        bd.px(bx, by + 1, P(M))
    # hill and path
    bd.layer()
    hill = lambda x: 234 - 10 * math.exp(-((x - 128) / 60.0) ** 2) + 4 * math.sin(x / 13.0)
    bd.profile(hill, P(G, CHECK), edge=P(G))
    for y in range(226, YB):
        hw = 6 + (y - 226) * 0.9
        bd.hline(128 - hw, 128 + hw, y, P(Y, DOTS))
    return bd


def forest():
    rnd = random.Random(6)
    bd = Backdrop()
    bd.band(140, YB, P(B, DOTS8))
    for cx in range(8, 252, 16):
        pine_cols(bd, cx + rnd.randint(-3, 3), 236, rnd.randint(44, 72), P(B, CHECK))
    near = [(24, 110), (70, 90), (118, 128), (166, 96), (214, 118)]
    for cx, h in near:
        pine_cols(bd, cx, 247, h, P(G, CHECK), P(M))
    # ground with ferns and mushrooms
    bd.layer()
    bd.band(240, YB, P(G, DOTS))
    bd.hline(XL, XR - 1, 247, P(G))
    for fx in range(10, 250, 22):
        for k in (-2, 0, 2):
            bd.line(fx, 246, fx + k * 2, 240 - abs(k), P(G))
    for mx in (46, 96, 142, 190, 238):
        bd.rect(mx, 243, 2, 4, P(W))
        bd.ellipse(mx + 0.5, 242, 2, P(R), rx=3)
        bd.px(mx - 1, 241, P(W))
    # owl, fireflies
    bd.layer()
    bd.rect(116, 165, 7, 6, P(M))
    bd.px(117, 166, P(Y))
    bd.px(121, 166, P(Y))
    bd.px(119, 168, P(R))
    for x, y in [(44, 150), (92, 196), (142, 176), (190, 140), (238, 190), (60, 120),
                 (100, 140), (160, 210), (210, 160)]:
        bd.px(x, y, P(Y))
    return bd


def moonbase():
    rnd = random.Random(7)
    bd = Backdrop()
    # earth in the sky
    bd.ellipse(200, 60, 18, P(B))
    bd.layer()
    for cx, cy, r in [(194, 52, 7), (206, 66, 6), (198, 70, 4)]:
        bd.ellipse(cx, cy, r, P(G))
    bd.ellipse(200, 60, 18, P(W, DOTS8))
    for y in range(46, 76):
        bd.hline(210, 214, y, P(K, CHECK))
    # distant ridge
    bd.layer()
    ridge = lambda x: 190 + 8 * math.sin(x / 21.0) + 4 * math.sin(x / 6.0 + 1)
    bd.profile(ridge, P(C, CHECK), edge=P(C))
    # surface
    bd.layer()
    surf = lambda x: 214 + 3 * math.sin(x / 31.0)
    bd.profile(surf, P(W, DOTS), edge=P(W))
    bd.layer()
    for cx, cy, r in [(30, 230, 7), (84, 238, 5), (170, 228, 8), (226, 238, 6), (130, 242, 4)]:
        bd.ellipse(cx, cy, r * 0.5, P(K), rx=r)
        bd.hline(cx - r * 0.8, cx + r * 0.8, cy - r * 0.5, P(W))
    # dome base
    bd.layer()
    for y in range(178, 215):
        hw = 30 * math.sqrt(max(0.0, 1 - ((y - 214) / 36.0) ** 2))
        bd.hline(70 - hw, 70 + hw, y, P(C, CHECK))
    bd.layer()
    for y in range(184, 214, 8):
        hw = 30 * math.sqrt(max(0.0, 1 - ((y - 214) / 36.0) ** 2))
        bd.hline(70 - hw, 70 + hw, y, P(C))
    for wx in (56, 66, 76):
        bd.rect(wx, 200, 4, 4, P(Y))
    bd.rect(100, 204, 30, 10, P(W))                      # tunnel module
    bd.rect(102, 206, 26, 6, P(B, VLINE))
    # radar dish
    bd.vline(146, 186, 213, P(W))
    bd.ellipse(146, 184, 6, P(W, CHECK), rx=8)
    bd.line(146, 184, 152, 176, P(W))
    bd.px(152, 175, P(R))
    # rocket on its pad
    bd.layer()
    bd.rect(182, 208, 26, 6, P(M, BRICK))
    bd.rect(190, 160, 10, 48, P(W))
    bd.rect(190, 160, 10, 48, P(C, VLINE))
    bd.tri(195, 140, 160, 0.3, P(W))
    bd.vline(195, 128, 140, P(W))
    bd.rect(192, 172, 6, 6, P(B))
    bd.poly([(190, 192), (184, 208), (190, 204)], P(R))
    bd.poly([(200, 192), (206, 208), (200, 204)], P(R))
    bd.hline(190, 199, 182, P(R))
    return bd


def arctic():
    bd = Backdrop()
    # aurora
    for k, (col, y0) in enumerate([(G, 40), (C, 52), (G, 64)]):
        runs = []
        for x in range(XL, XR):
            y = y0 + 10 * math.sin(x / 26.0 + k) + 4 * math.sin(x / 9.0)
            runs.append((y, 7 + 3 * math.sin(x / 13.0)))
        bd.cols(XL, runs, P(col, CHECK if k != 1 else DOTS))
    # mountains of ice
    bd.layer()
    ice = lambda x: 170 + 18 * abs(math.sin(x / 30.0)) + 6 * math.sin(x / 8.0)
    bd.profile(ice, P(C, CHECK), edge=P(W))
    # sea
    bd.layer()
    bd.rect(XL, 214, XR - XL, YB - 214, P(B))
    bd.layer()
    for i, y in enumerate(range(217, 246, 5)):
        for k in range(9):
            x = (k * 29 + i * 13) % 240 + XL
            bd.hline(x, x + 5, y, P(C, CHECK))
    # icebergs
    bd.layer()
    for pts in ([(20, 214), (34, 186), (48, 192), (62, 214)],
                [(180, 214), (190, 196), (204, 190), (214, 200), (226, 214)]):
        bd.poly(pts, P(W))
        bd.poly([(x, y if y < 214 else 230) for x, y in pts], P(C, DOTS))
    bd.poly([(20, 214), (34, 186), (48, 192), (62, 214)], P(W))
    bd.poly([(180, 214), (190, 196), (204, 190), (214, 200), (226, 214)], P(W))
    # ice floe with igloo
    bd.layer()
    bd.rect(84, 210, 88, 6, P(W))
    bd.hline(84, 171, 215, P(C))
    for y in range(186, 210):
        hw = 22 * math.sqrt(max(0.0, 1 - ((y - 210) / 24.0) ** 2))
        bd.hline(128 - hw, 128 + hw, y, P(W))
    bd.layer()
    for y in range(187, 210):
        hw = 22 * math.sqrt(max(0.0, 1 - ((y - 210) / 24.0) ** 2))
        bd.hline(128 - hw, 128 + hw, y, P(C, BRICK))
    bd.rect(122, 200, 12, 10, P(K))
    bd.ellipse(128, 200, 5, P(K), rx=6)
    # penguins
    for px in (96, 104, 156):
        bd.rect(px, 202, 4, 8, P(K))
        bd.rect(px + 1, 204, 2, 5, P(W))
        bd.px(px + 3, 203, P(Y))
        bd.hline(px, px + 3, 209, P(Y))
    return bd


BACKDROPS = [("bg_city", city), ("bg_mountains", mountains), ("bg_desert", desert),
             ("bg_harbour", harbour), ("bg_castle", castle), ("bg_forest", forest),
             ("bg_moon", moonbase), ("bg_arctic", arctic)]


def emit(f, label, bd):
    data = bd.bytecode()
    f.write(f"{label}:                        ; {len(bd.ops)} ops\n")
    for i in range(0, len(data), 16):
        f.write("        dc.b    " + ",".join(str(v) for v in data[i:i + 16]) + "\n")
    f.write("        even\n")
    return len(data)


def main():
    total = 0
    with open("bgdata.inc", "w") as f:
        f.write("; generated by backdrops.py - do not edit by hand\n")
        for lab, fn in BACKDROPS:
            n = emit(f, lab, fn())
            print(f"{lab}: {n} bytes")
            total += n
    print("total", total)


if __name__ == "__main__":
    main()
