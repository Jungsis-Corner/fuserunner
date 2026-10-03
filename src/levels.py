#!/usr/bin/env python3
"""Level data for FUSE RUNNER plus a reachability check.

Writes levels.inc. The check replays Jack's physics exactly as in
fuse.asm (1/16 pixel units, 25 Hz loop) and makes sure every bomb can be
touched from some reachable standing position.
Run:  python3 levels.py          (writes levels.inc, prints report)
"""
import sys

FLOOR = (4, 248, 248, 8)

# platform rect: (x, y, w, h); bombs: (x, y) with x multiple of 4, 8x8
LEVELS = [
    dict(name="city", bg="bg_city", start=(122, 232), moon=(210, 48), bricks=(6, 2, 3, 0),
         spawn=(60, 190, 124),
         plats=[(24, 200, 56, 6), (176, 200, 56, 6), (96, 160, 64, 6), (16, 116, 52, 6),
                (188, 116, 52, 6), (88, 72, 80, 6)],
         bombs=[(16, 240), (32, 240), (216, 240), (232, 240),
                (124, 100), (124, 116), (124, 132),
                (32, 192), (48, 192), (64, 192), (184, 192), (200, 192), (216, 192),
                (24, 108), (44, 108), (200, 108), (220, 108),
                (104, 64), (144, 64), (8, 150), (8, 166)]),
    dict(name="mountains", bg="bg_mountains", start=(122, 232), moon=(210, 40), bricks=(7, 2, 3, 0),
         spawn=(30, 220, 128),
         plats=[(36, 208, 48, 6), (172, 208, 48, 6), (104, 180, 48, 6), (52, 144, 48, 6),
                (156, 144, 48, 6), (12, 100, 40, 6), (204, 100, 40, 6), (100, 108, 56, 6),
                (104, 56, 48, 6)],
         bombs=[(8, 240), (24, 240), (224, 240), (240, 240),
                (44, 200), (64, 200), (180, 200), (200, 200), (112, 172), (136, 172),
                (60, 136), (84, 136), (164, 136), (188, 136),
                (20, 92), (36, 92), (212, 92), (228, 92),
                (116, 100), (136, 100), (112, 48), (136, 48),
                (240, 160), (240, 176)]),
    dict(name="desert", bg="bg_desert", start=(122, 232), moon=(128, 42), bricks=(6, 2, 3, 0),
         spawn=(48, 208, 128),
         plats=[(20, 212, 40, 6), (68, 184, 40, 6), (116, 156, 40, 6), (164, 184, 40, 6),
                (212, 212, 32, 6), (20, 128, 48, 6), (188, 128, 48, 6), (92, 96, 72, 6),
                (28, 60, 40, 6), (188, 60, 40, 6)],
         bombs=[(96, 240), (152, 240),
                (124, 112), (124, 128), (124, 144),
                (28, 204), (44, 204), (80, 176), (96, 176), (172, 176), (188, 176),
                (220, 204), (232, 204),
                (28, 120), (48, 120), (196, 120), (216, 120),
                (100, 88), (148, 88),
                (36, 52), (52, 52), (196, 52), (212, 52), (8, 170)]),
    dict(name="harbour", bg="bg_harbour", start=(122, 232), moon=(210, 48), bricks=(7, 2, 3, 0),
         spawn=(30, 226, 128),
         plats=[(8, 200, 64, 6), (184, 200, 64, 6), (92, 176, 72, 6), (40, 140, 48, 6),
                (168, 140, 48, 6), (100, 112, 56, 6), (8, 80, 48, 6), (200, 80, 48, 6),
                (96, 52, 64, 6)],
         bombs=[(124, 192), (124, 208), (124, 224),
                (16, 192), (32, 192), (48, 192), (196, 192), (212, 192), (228, 192),
                (104, 168), (144, 168),
                (48, 132), (68, 132), (176, 132), (196, 132),
                (112, 104), (136, 104),
                (16, 72), (32, 72), (208, 72), (228, 72),
                (108, 44), (124, 44), (140, 44)]),
    dict(name="castle", bg="bg_castle", start=(122, 232), moon=(172, 40), bricks=(7, 2, 3, 0),
         spawn=(44, 212, 128),
         plats=[(4, 216, 40, 6), (208, 216, 44, 6), (60, 188, 32, 6), (164, 188, 32, 6),
                (108, 164, 40, 6), (20, 148, 40, 6), (196, 148, 40, 6), (68, 116, 28, 6),
                (160, 116, 28, 6), (104, 84, 48, 6), (24, 64, 40, 6), (192, 64, 40, 6),
                (96, 200, 6, 48), (154, 200, 6, 48)],
         bombs=[(12, 208), (236, 208), (96, 192), (152, 192),
                (64, 180), (80, 180), (168, 180), (184, 180),
                (116, 156), (132, 156), (28, 140), (44, 140), (204, 140), (220, 140),
                (72, 108), (84, 108), (164, 108), (176, 108),
                (112, 76), (132, 76), (32, 56), (48, 56), (200, 56), (216, 56)]),
    dict(name="forest", bg="bg_forest", start=(122, 232), moon=(210, 48), bricks=(6, 3, 2, 0),
         spawn=(40, 216, 100),
         plats=[(24, 208, 56, 6), (120, 196, 40, 6), (192, 172, 52, 6), (60, 160, 44, 6),
                (12, 116, 36, 6), (128, 128, 48, 6), (204, 100, 40, 6), (64, 84, 56, 6),
                (144, 56, 44, 6)],
         bombs=[(220, 240), (108, 176), (108, 192), (108, 208),
                (32, 200), (48, 200), (64, 200), (128, 188), (144, 188),
                (200, 164), (216, 164), (232, 164), (68, 152), (88, 152),
                (32, 108), (136, 120), (156, 120), (208, 92), (228, 92),
                (72, 76), (92, 76), (108, 76), (152, 48), (172, 48)]),
    dict(name="moon", bg="bg_moon", start=(122, 232), moon=(0, 0), bricks=(7, 5, 1, 0),
         spawn=(40, 216, 128),
         plats=[],
         bombs=[(28, 120), (28, 140), (28, 160), (28, 180),
                (84, 120), (84, 140), (84, 160), (84, 180),
                (164, 120), (164, 140), (164, 160), (164, 180),
                (220, 120), (220, 140), (220, 160), (220, 180),
                (108, 100), (124, 92), (140, 100), (124, 140), (124, 180),
                (60, 240), (188, 240)]),
    dict(name="arctic", bg="bg_arctic", start=(122, 232), moon=(0, 0), bricks=(7, 5, 1, 0),
         spawn=(40, 216, 100),
         plats=[(64, 176, 6, 72), (186, 176, 6, 72), (20, 176, 44, 6), (192, 176, 44, 6),
                (100, 200, 56, 6), (40, 128, 48, 6), (168, 128, 48, 6), (104, 140, 48, 6),
                (126, 72, 6, 56), (60, 72, 40, 6), (156, 72, 40, 6)],
         bombs=[(24, 240), (40, 240), (212, 240), (228, 240),
                (28, 168), (48, 168), (200, 168), (220, 168),
                (88, 240), (160, 240), (108, 192), (140, 192),
                (48, 120), (72, 120), (176, 120), (200, 120),
                (112, 132), (136, 132), (68, 64), (88, 64), (164, 64), (184, 64)]),
]

# ---------------------------------------------------------------- physics
# keep in sync with fuse.asm
XMIN, XMAX = 4, 252 - 12
PF_CEIL, SPRH = 20, 16
WALKV, JUMPV, GRAV, SHORTV, GLIDEV, MAXFALL, FASTV = 32, 190, 8, 40, 14, 96, 64


def body_move(s, rects):
    """s: dict x,y,vx,vy,gnd (1/16 px). Mirrors body_move in fuse.asm."""
    d0 = s['x'] + s['vx']
    d1 = d0 >> 4
    if d1 < XMIN:
        d1 = XMIN; d0 = d1 << 4
    elif d1 > XMAX:
        d1 = XMAX; d0 = d1 << 4
    top = s['y'] >> 4
    bot = top + SPRH - 1
    left, right = d1 + 1, d1 + 10
    for rx, ry, rw, rh in rects:
        if right < rx or left >= rx + rw:
            continue
        if bot < ry or top >= ry + rh:
            continue
        d0 = s['x']
        break
    s['x'] = d0
    d1 = d0 >> 4
    left, right = d1 + 1, d1 + 10
    oldtop = s['y'] >> 4
    ny = s['y'] + s['vy']
    newtop = ny >> 4
    if s['vy'] >= 0:
        ob, nb = oldtop + SPRH, newtop + SPRH
        best = None
        for rx, ry, rw, rh in rects:
            if right < rx or left >= rx + rw:
                continue
            if ob <= ry <= nb and (best is None or ry < best):
                best = ry
        if best is not None:
            ny = (best - SPRH) << 4
            s['vy'] = 0
            s['gnd'] = 1
        else:
            s['gnd'] = 0
    else:
        best = -1
        for rx, ry, rw, rh in rects:
            if right < rx or left >= rx + rw:
                continue
            ub = ry + rh
            if newtop < ub <= oldtop and ub > best:
                best = ub
        if best >= 0:
            ny = best << 4
            s['vy'] = 0
        if ny < PF_CEIL << 4:
            ny = PF_CEIL << 4
            s['vy'] = 0
        s['gnd'] = 0
    s['y'] = ny


def step(s, keys, prev, rects):
    """keys: set of 'L','R','J','D'. Mirrors update_jack."""
    vx = 0
    if 'L' in keys:
        vx = -WALKV
    if 'R' in keys:
        vx = WALKV
    s['vx'] = vx
    j = 'J' in keys
    pj = 'J' in prev
    vy = s['vy']
    if s['gnd']:
        if j and not pj:
            vy = -JUMPV
            s['gnd'] = 0
    else:
        vy += GRAV
        if vy < 0:
            if not j and vy < -SHORTV:
                vy = -SHORTV
        else:
            if 'D' in keys:
                vy = max(vy, FASTV)
            elif j:
                vy = min(vy, GLIDEV)
        vy = min(vy, MAXFALL)
    s['vy'] = vy
    body_move(s, rects)


def touched(s, bombs, hit):
    px, py = s['x'] >> 4, s['y'] >> 4
    l, r, t, b = px + 1, px + 10, py, py + SPRH - 1
    for i, (bx, by) in enumerate(bombs):
        if r >= bx and l <= bx + 7 and b >= by and t <= by + 7:
            hit.add(i)


def standing_spots(rects):
    """all x positions (step 4) where Jack can stand, as (x, y_top)"""
    spots = set()
    for rx, ry, rw, rh in rects:
        for x in range(XMIN, XMAX + 1, 4):
            if x + 10 >= rx and x + 1 < rx + rw:
                s = dict(x=x << 4, y=(ry - SPRH) << 4, vx=0, vy=0, gnd=1)
                # must not be inside another rect
                top, bot = ry - SPRH, ry - 1
                if any(not (x + 10 < qx or x + 1 >= qx + qw or bot < qy or top >= qy + qh)
                       for qx, qy, qw, qh in rects):
                    continue
                spots.add((x, ry - SPRH))
    return spots


def simulate(level):
    rects = [FLOOR] + level['plats']
    bombs = level['bombs']
    hit = set()
    start = level['start']
    seen = set()
    queue = [start]
    spots_all = standing_spots(rects)
    plans = []
    for dirk in (None, 'L', 'R'):
        for delay in (0, 8, 16):
            for hold in (1, 4, 8, 14, 22, 999):
                plans.append((dirk, delay, hold, False))
    for dirk in ('L', 'R'):
        plans.append((dirk, 0, 0, True))           # walk off an edge
        plans.append((dirk, 0, 999, True))         # walk off and glide
    while queue:
        sx, sy = queue.pop()
        if (sx, sy) in seen:
            continue
        seen.add((sx, sy))
        for dirk, delay, hold, walkoff in plans:
            s = dict(x=sx << 4, y=sy << 4, vx=0, vy=0, gnd=1)
            prev = set()
            for t in range(220):
                keys = set()
                if walkoff:
                    keys.add(dirk)
                    if hold and not s['gnd']:
                        keys.add('J')
                else:
                    if t == 1 or (t > 1 and t <= hold):
                        keys.add('J')
                    if dirk and t >= delay:
                        keys.add(dirk)
                step(s, keys, prev, rects)
                prev = keys
                touched(s, bombs, hit)
                if t > 2 and s['gnd'] and not walkoff:
                    break
                if walkoff and t > 2 and s['gnd'] and s['y'] >> 4 != sy:
                    break
            if s['gnd']:
                land = ((s['x'] >> 4) // 4 * 4, s['y'] >> 4)
                if land in spots_all and land not in seen:
                    queue.append(land)
        # walking along the surface touches floor-level bombs
        s = dict(x=sx << 4, y=sy << 4, vx=0, vy=0, gnd=1)
        touched(s, bombs, hit)
    return hit, seen


def check_static(i, lv):
    errs = []
    rects = [FLOOR] + lv['plats']
    if len(lv['bombs']) > 24:
        errs.append(f"too many bombs ({len(lv['bombs'])})")
    for (bx, by) in lv['bombs']:
        if bx % 4:
            errs.append(f"bomb x {bx} not multiple of 4")
        if bx < 4 or bx + 8 > 252 or by < 20 or by + 8 > 248:
            errs.append(f"bomb {bx},{by} outside playfield")
        for rx, ry, rw, rh in rects:
            if bx < rx + rw and bx + 8 > rx and by < ry + rh and by + 8 > ry:
                errs.append(f"bomb {bx},{by} overlaps platform {rx},{ry}")
    for sx in lv['spawn']:
        for rx, ry, rw, rh in rects:
            if sx + 10 >= rx and sx + 1 < rx + rw and ry < 20 + 16:
                errs.append(f"spawn {sx} blocked")
    return errs


def emit(path):
    with open(path, "w") as f:
        f.write("; generated by levels.py - do not edit by hand\n")
        f.write(f"NLEV    equ     {len(LEVELS)}\n")
        f.write("lvltab: dc.w    " + ",".join(f"lvl{i+1}-lvltab" for i in range(len(LEVELS))) + "\n")
        for i, lv in enumerate(LEVELS):
            n = i + 1
            f.write(f"\n; --- round {n}: {lv['name']}\n")
            f.write(f"lvl{n}:   dc.w    2,{lv['start'][0]},{lv['start'][1]}\n")
            f.write(f"        dc.w    plats{n}-lvl{n},bombs{n}-lvl{n},spawn{n}-lvl{n},{lv['bg']}-lvl{n}\n")
            f.write(f"        dc.w    {lv['moon'][0]},{lv['moon'][1]}            ; moon x,y (0 = none)\n")
            f.write("        dc.w    " + ",".join(str(c) for c in lv['bricks']) + "        ; brick colours\n")
            f.write(f"plats{n}: dc.w    {','.join(map(str, FLOOR))}\n")
            for p in lv['plats']:
                f.write(f"        dc.w    {','.join(map(str, p))}\n")
            f.write("        dc.w    -1\n")
            f.write(f"bombs{n}:")
            for j in range(0, len(lv['bombs']), 6):
                f.write("\t" if j == 0 else "        ")
                f.write("dc.w    " + ", ".join(f"{x},{y}" for x, y in lv['bombs'][j:j + 6]) + "\n")
            f.write("        dc.w    -1\n")
            f.write(f"spawn{n}: dc.w    {','.join(map(str, lv['spawn']))}\n")


def main():
    ok = True
    for i, lv in enumerate(LEVELS):
        errs = check_static(i, lv)
        hit, seen = simulate(lv)
        miss = [lv['bombs'][k] for k in range(len(lv['bombs'])) if k not in hit]
        status = "OK" if not errs and not miss else "PROBLEM"
        print(f"round {i+1} {lv['name']:10s} bombs {len(lv['bombs']):2d}  spots {len(seen):3d}  {status}")
        for e in errs:
            print("   ", e)
        if miss:
            print("    unreachable bombs:", miss)
        ok = ok and status == "OK"
    emit("levels.inc")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
