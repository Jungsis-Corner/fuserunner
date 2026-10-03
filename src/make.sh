#!/bin/sh
# Builds FUSE RUNNER (one binary, German/English selectable in the menu).
# Needs vasm (vasmm68k_mot) and Python 3; preview.py also needs Pillow.
# Optional: qxltool (32-bit build) in the PATH to create fuserunner.win.
python3 gfx.py || exit 1
python3 backdrops.py >/dev/null || exit 1
python3 music.py || exit 1
python3 splash.py || exit 1        # loading screen: fuse_scr + splash.inc
python3 levels.py || exit 1          # writes levels.inc, checks every bomb is reachable
vasmm68k_mot -Fbin -m68000 -quiet -o fuse_bin fuse.asm || exit 1
# fuserunner: same binary plus XTcc trailer (job header for sQLux/Q-emuLator/qxltool)
python3 -c "import struct;d=open('fuse_bin','rb').read();open('fuserunner','wb').write(d+b'XTcc'+struct.pack('>I',4096))"
LEN=$(wc -c < fuse_bin | tr -d ' ')
RES=$(( (LEN + 1023) / 1024 * 1024 ))
cat > INSTALL_bas <<EOB
10 REMark FUSE RUNNER - create job file with QDOS header and run it
20 REMark Laufwerk anpassen / change the drive: mdv1_ flp1_ win1_ dos1_
30 d\$="win1_"
40 a=RESPR($RES)
50 LBYTES d\$&"fuse_bin",a
60 SEXEC d\$&"fuserunner_exe",a,$LEN,4096
70 EXEC_W d\$&"fuserunner_exe"
EOB
cat > LOADER_bas <<EOB
10 REMark FUSE RUNNER - Start per CALL / start via CALL (no file header needed)
20 a=RESPR($RES)
30 LBYTES win1_fuse_bin,a
40 CALL a+20
EOB
printf '10 MODE 8: LBYTES win1_fuse_scr,131072: EXEC_W win1_fuserunner\n' > boot
if command -v qxltool >/dev/null 2>&1; then
  rm -f fuserunner.win
  qxltool -w fuserunner.win 2 FUSE RUNNER </dev/null >/dev/null 2>&1
  printf 'write boot\nwrite fuse_scr\nwrite fuserunner\nquit\n' | qxltool -w fuserunner.win >/dev/null 2>&1
  echo "fuserunner.win created"
fi
ls -l fuse_bin fuserunner
