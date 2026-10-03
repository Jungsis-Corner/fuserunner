#!/bin/bash
# emu.sh [vasm options]  - build fuse.asm (with optional -D test switches) and start it
# in sQLux on a virtual display (Xvfb :9), booting from emu/mdv1/ (a host directory).
# Examples:  ./tools/emu.sh                    normal build
#            ./tools/emu.sh -DSTARTRD=5         start in round 5
#            ./tools/emu.sh -DDEBUG=1           frames per loop shown in the HUD
T=$(cd "$(dirname "$0")/.." && pwd)          # repository root (src/ lives here)
TC=${TOOLCHAIN:-$T/toolchain}
mkdir -p "$T/emu/mdv1" "$T/emu/shots"
cd "$T/src" || exit 1
"$TC/vasm/vasmm68k_mot" -Fbin -m68000 -quiet "$@" -o "$T/emu/t.bin" fuse.asm || exit 1
python3 -c "import struct;d=open('$T/emu/t.bin','rb').read();open('$T/emu/mdv1/fuserunner','wb').write(d+b'XTcc'+struct.pack('>I',4096))"
cp fuse_scr "$T/emu/mdv1/" 2>/dev/null
printf '10 EXEC_W mdv1_fuserunner\n' > "$T/emu/mdv1/BOOT"; cp "$T/emu/mdv1/BOOT" "$T/emu/mdv1/boot"
cat > "$T/emu/sqlux.ini" <<EOI
SYSROM = Minerva_1.98a1.bin
ROMDIR = $TC/sQLux/roms/
RAMTOP = 640
FAST_STARTUP = 1
SKIP_BOOT = 1
DEVICE = MDV1,$T/emu/mdv1/,qdos-like
BOOT_DEVICE = MDV1
SPEED = 1
SOUND = 5
EOI
pgrep Xvfb >/dev/null || (Xvfb :9 -screen 0 1024x768x24 >/dev/null 2>&1 &); sleep 1
pkill -x sqlux; sleep 0.5
# SDL "disk" audio driver: sound is written to emu/sound.raw (44.1 kHz, 16 bit, stereo)
(SDL_AUDIODRIVER=disk SDL_DISKAUDIOFILE="$T/emu/sound.raw" DISPLAY=:9 \
  "$TC/sQLux/build/sqlux" -f "$T/emu/sqlux.ini" >"$T/emu/sqlux.log" 2>&1 &)
echo "started - title/menu appears after about 12-14 s (game + loading screen)"
