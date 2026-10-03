#!/usr/bin/env python3
"""Graphics generator for FUSE RUNNER (Sinclair QL, Mode 8).

Writes gfx.inc with pre-shifted sprites including masks.
Mode 8: one word = 4 pixels. Pixel p (0..3) in a word:
  G = bit 15-2p, F (flash) = bit 14-2p, R = bit 7-2p, B = bit 6-2p
Sprite format: per shift (0..3) 16 lines x 4 words x (mask, data) = 256 bytes.
Colours: K black, B blue, R red, M magenta, G green, C cyan, Y yellow, W white,
'.' transparent.
"""

COL = {'K': 0, 'B': 1, 'R': 2, 'M': 3, 'G': 4, 'C': 5, 'Y': 6, 'W': 7}


def pixbits(c, p):
    w = 0
    if c & 4: w |= 1 << (15 - 2 * p)
    if c & 2: w |= 1 << (7 - 2 * p)
    if c & 1: w |= 1 << (6 - 2 * p)
    return w


def clrbits(p):
    return (~((1 << (15 - 2 * p)) | (1 << (14 - 2 * p)) |
              (1 << (7 - 2 * p)) | (1 << (6 - 2 * p)))) & 0xffff


def encode_row(row, shift, nwords):
    """row: string, '.' = transparent. returns list of (mask, data)."""
    out = []
    for w in range(nwords):
        mask, data = 0xffff, 0
        for p in range(4):
            col = w * 4 + p - shift
            if 0 <= col < len(row) and row[col] != '.':
                c = COL[row[col]]
                mask &= clrbits(p)
                data |= pixbits(c, p)
        out.append((mask, data))
    return out


def sprite(rows, shifts=4, nwords=4, h=16):
    rows = rows + ['.' * 12] * (h - len(rows))
    words = []
    for s in range(shifts):
        for r in rows:
            for m, d in encode_row(r, s, nwords):
                words += [m, d]
    return words


def mirror(rows):
    return [r[::-1] for r in rows]


def emit(f, label, words):
    f.write(f"{label}:\n")
    for i in range(0, len(words), 8):
        f.write("        dc.w    " + ",".join(f"${w:04x}" for w in words[i:i + 8]) + "\n")


HEAD = [
    "....Y.......",
    "....C.......",
    "...CCCCC....",
    "..CCCCCCC...",
    "..CCCWWKC...",
    "..CCCWWKC...",
    "...CCCCC....",
]

JACK = {
    'stand': HEAD + [
        "....RRR.....",
        "..RRRRRRR...",
        ".RR.RRR.RR..",
        ".W..RRR..W..",
        "...RRRRR....",
        "...WW.WW....",
        "...WW.WW....",
        "...WW.WW....",
        "..YYY.YYY...",
    ],
    'walk1': HEAD + [
        "....RRR.....",
        "..RRRRRRR...",
        ".RR.RRR.RR..",
        ".W..RRR..W..",
        "...RRRRR....",
        "..WW...WW...",
        ".WW.....WW..",
        ".WW.....WW..",
        "YYY.....YYY.",
    ],
    'walk2': HEAD + [
        "....RRR.....",
        "...RRRRR....",
        "...RRRRRW...",
        "..WRRRRR....",
        "...RRRRR....",
        "....WWW.....",
        "....WWW.....",
        "....WW......",
        "...YYYY.....",
    ],
    'jump': HEAD + [
        ".W..RRR..W..",
        ".RRRRRRRRR..",
        "...RRRRR....",
        "...RRRRR....",
        "...RRRRR....",
        "..WW...WW...",
        ".WW.....WW..",
        ".YY.....YY..",
    ],
    'glide': HEAD + [
        "....RRR.....",
        "WRRRRRRRRRRW",
        "...RRRRR....",
        "...RRRRR....",
        "...RRRRR....",
        "....WWW.....",
        "....WWW.....",
        "....YYY.....",
    ],
}

WALKER = [
    [
        "............",
        "............",
        "...GGGGGG...",
        "..GGGGGGGG..",
        "..GYKGGYKG..",
        "..GGGGGGGG..",
        "..GKKKKKKG..",
        "...GGGGGG...",
        ".CCCCCCCCCC.",
        ".CGGGGGGGGC.",
        ".CGGGGGGGGC.",
        ".CCCCCCCCCC.",
        "..W......W..",
        ".WKW....WKW.",
        ".WWW....WWW.",
    ],
    [
        "............",
        "............",
        "...GGGGGG...",
        "..GGGGGGGG..",
        "..GKYGGKYG..",
        "..GGGGGGGG..",
        "..GGKKKKGG..",
        "...GGGGGG...",
        ".CCCCCCCCCC.",
        ".CGGGGGGGGC.",
        ".CGGGGGGGGC.",
        ".CCCCCCCCCC.",
        "............",
        ".WWW....WWW.",
        ".WKW....WKW.",
        "..W......W..",
    ],
]

SEEKER = [
    [
        "............",
        "............",
        "M..........M",
        "MM........MM",
        ".MM.MMMM.MM.",
        "..MMMMMMMM..",
        "...MWWWWM...",
        "...MWKKWM...",
        "...MWWWWM...",
        "....MMMM....",
        ".....RR.....",
    ],
    [
        "............",
        "............",
        "............",
        "............",
        "....MMMM....",
        "..MMMMMMMM..",
        ".MMMWWWWMMM.",
        "MM.MWKKWM.MM",
        "M..MWWWWM..M",
        "....MMMM....",
        ".....RR.....",
    ],
]

BOMB_N = [
    ".....Y..",
    "....W...",
    "..RRRR..",
    ".RRRRRR.",
    ".RWRRRR.",
    ".RRRRRR.",
    ".RRRRRR.",
    "..RRRR..",
]
BOMB_L1 = [
    "....YWY.",
    "....WY..",
    "..YYYY..",
    ".YYYYYY.",
    ".YWYYYY.",
    ".YYYYYY.",
    ".YYYYYY.",
    "..YYYY..",
]
BOMB_L2 = [
    ".....W..",
    "....Y...",
    "..RRRR..",
    ".RRRRRR.",
    ".RWRRRR.",
    ".RRRRRR.",
    ".RRRRRR.",
    "..RRRR..",
]


def recolor(rows, table):
    return [''.join(table.get(ch, ch) for ch in r) for r in rows]


ICE_WALK = {'G': 'C', 'C': 'W', 'Y': 'W', 'K': 'B'}
ICE_SEEK = {'M': 'C', 'R': 'W', 'K': 'B'}

PAD3 = ["............"] * 3

HEART = PAD3 + [
    "..RR....RR..",
    ".RRRR..RRRR.",
    "RRWRRRRRRRRR",
    "RWRRRRRRRRRR",
    "RRRRRRRRRRRR",
    ".RRRRRRRRRR.",
    "..RRRRRRRR..",
    "...RRRRRR...",
    "....RRRR....",
    ".....RR.....",
]
SNOW = PAD3 + [
    ".....C......",
    "..C..C..C...",
    "...C.C.C....",
    "....CCC.....",
    "CCCCCWCCCCC.",
    "....CCC.....",
    "...C.C.C....",
    "..C..C..C...",
    ".....C......",
]
BLAST = PAD3 + [
    "Y....Y....Y.",
    ".Y...Y...Y..",
    "..Y.YYY.Y...",
    "...YYWYY....",
    "YYYYWWWYYYY.",
    "...YYWYY....",
    "..Y.YYY.Y...",
    ".Y...Y...Y..",
    "Y....Y....Y.",
]
EXPLODE = [
    PAD3 + [
        "............",
        ".....Y......",
        "...Y.W.Y....",
        "....WWW.....",
        "..YWWWWWY...",
        "....WWW.....",
        "...Y.W.Y....",
        ".....Y......",
    ],
    PAD3 + [
        "..R...R...R.",
        "...R..Y..R..",
        "....RYYYR...",
        ".R.YY.W.YY.R",
        "..RYW...WYR.",
        ".R.YY.W.YY.R",
        "....RYYYR...",
        "...R..Y..R..",
        "..R...R...R.",
    ],
]

HOPPER = [
    ["............"] * 6 + [
        "....YYYY....",
        "...YYYYYY...",
        "..YKYYYYKY..",
        "..YYYYYYYY..",
        "...YRRRRY...",
        "....YYYY....",
        "...M.MM.M...",
        "....MMMM....",
        "...M.MM.M...",
        "..RRR..RRR..",
    ],
    [
        "....YYYY....",
        "...YYYYYY...",
        "..YKYYYYKY..",
        "..YYYYYYYY..",
        "...YRRRRY...",
        "....YYYY....",
        ".....MM.....",
        "....M..M....",
        ".....MM.....",
        "....M..M....",
        ".....MM.....",
        "....M..M....",
        ".....MM.....",
        "....MMMM....",
        "..RRR..RRR..",
        "............",
    ],
]
ICE_HOP = {'Y': 'C', 'M': 'W', 'R': 'B', 'K': 'B'}


def main():
    with open("gfx.inc", "w") as f:
        f.write("; generated by gfx.py - do not edit by hand\n")
        f.write("        even\n")
        emit(f, "clrmask", [clrbits(p) for p in range(4)])
        emit(f, "pixtab", [pixbits(c, p) for c in range(8) for p in range(4)])
        emit(f, "fullw", [pixbits(c, 0) | pixbits(c, 1) | pixbits(c, 2) | pixbits(c, 3) for c in range(8)])
        pm = [(~clrbits(p)) & 0xffff for p in range(4)]
        emit(f, "lmask", [pm[0] * 0 | sum(pm[q] for q in range(p, 4)) for p in range(4)])
        emit(f, "rmask", [sum(pm[q] for q in range(0, n)) for n in range(5)])
        # pattern masks: [mode][y & 7][word 0/1] for 8 pixels starting at x = 0 mod 8
        from backdrops import pat
        words = []
        for mode in range(8):
            for y in range(8):
                for w in range(2):
                    m = 0
                    for p in range(4):
                        if pat(mode, w * 4 + p, y):
                            m |= pm[p]
                    words.append(m)
        emit(f, "pattab", words)
        # Jack: index = frame*2 + direction (0 = right, 1 = left)
        words = []
        for name in ['stand', 'walk1', 'walk2', 'jump', 'glide']:
            words += sprite(JACK[name]) + sprite(mirror(JACK[name]))
        emit(f, "spr_jack", words)
        emit(f, "spr_walk", sprite(WALKER[0]) + sprite(WALKER[1]))
        emit(f, "spr_seek", sprite(SEEKER[0]) + sprite(SEEKER[1]))
        emit(f, "spr_walk_ice", sprite(recolor(WALKER[0], ICE_WALK)) + sprite(recolor(WALKER[1], ICE_WALK)))
        emit(f, "spr_seek_ice", sprite(recolor(SEEKER[0], ICE_SEEK)) + sprite(recolor(SEEKER[1], ICE_SEEK)))
        # bonus items: type*2 + frame (0 = life, 1 = freeze, 2 = blast)
        words = []
        for rows, alt in [(HEART, {'R': 'M'}), (SNOW, {'C': 'W', 'W': 'C'}), (BLAST, {'Y': 'R', 'W': 'Y'})]:
            words += sprite(rows) + sprite(recolor(rows, alt))
        emit(f, "spr_bonus", words)
        emit(f, "spr_hop", sprite(HOPPER[0]) + sprite(HOPPER[1]))
        emit(f, "spr_hop_ice", sprite(recolor(HOPPER[0], ICE_HOP)) + sprite(recolor(HOPPER[1], ICE_HOP)))
        emit(f, "spr_expl", sprite(EXPLODE[0]) + sprite(EXPLODE[1]))
        for lab, rows in [("bomb_n", BOMB_N), ("bomb_l1", BOMB_L1), ("bomb_l2", BOMB_L2)]:
            emit(f, lab, sprite(rows, shifts=1, nwords=2, h=8))


if __name__ == "__main__":
    main()
