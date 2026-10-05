# FUSE RUNNER – Projektnotizen für Claude Code

Ein Spiel im Stil von Bomb Jack für den **Sinclair QL**: 68000-Assembler, Mode 8 (256×256, 8 Farben),
läuft mit 25 Bildern/s auf einem QL mit Originaltakt, wenn mindestens 256K RAM vorhanden sind.
Idee: Jungsi · Code: Claude und Jungsi · www.jungsi.de

Die Kommentare im Quelltext sind englisch. Mit dem Nutzer (Jungsi) wird **deutsch** gesprochen.
Im Spiel ist Deutsch die Standardsprache, Englisch lässt sich im Menü umschalten.

## Aufbau des Repos

Das Projekt liegt unter `~/fuserunner` (WSL), die Werkzeugkette unter `~/toolchain` (also neben dem Repo, nicht darin).

```
src/fuse.asm        Hauptquelltext (~3700 Zeilen), bindet am Ende die *.inc-Dateien ein
src/gfx.py          Sprites + Pixel/Masken-Tabellen      -> gfx.inc
src/backdrops.py    9 Hintergründe als Bytecode         -> bgdata.inc
src/levels.py       Leveldaten + Erreichbarkeitsprüfung -> levels.inc
src/music.py        Melodien                            -> music.inc
src/splash.py       Ladebildschirm                      -> fuse_scr (roh, 32K) + splash.inc (RLE) + splash.png
src/preview.py      PNG-Vorschau aller Level/Hintergründe (braucht Pillow)
src/make.sh         kompletter Build (siehe unten)
tools/              Werkzeugkette + Emulator-Testhilfen (setup_tools.sh, emu.sh, key.sh, shot.sh, sound_notes.py)
LIESMICH_README.txt Anleitung für Spieler, zweisprachig DE/EN
screenshots/
```
Die `*.inc` werden erzeugt, also nie von Hand bearbeiten. Stattdessen das passende Python-Skript ändern.

## Werkzeuge einrichten

`./tools/setup_tools.sh` baut alles nach `./toolchain/` (relativ zum Aufrufverzeichnis).
Hier liegt die Werkzeugkette bereits fertig in `~/toolchain`:

- vasm (vasmm68k_mot)
- sQLux (Emulator, inklusive Minerva-ROM)
- qxltool

Gebraucht werden außerdem Python 3 mit Pillow und numpy, Xvfb, xdotool und ImageMagick (`import`).

**qxltool muss als 32-Bit-Programm gebaut werden** (`gcc -m32`, Paket gcc-multilib).
Die 64-Bit-Version schreibt kaputte WIN-Images und stürzt ab, weil `long` dort 8 Byte groß ist.

## Bauen

```
cd ~/fuserunner/src && PATH=~/toolchain/vasm:~/toolchain/qxltools:$PATH ./make.sh
```
make.sh startet der Reihe nach gfx.py, backdrops.py, music.py, splash.py und levels.py, danach vasm. Es erzeugt:

- `fuse_bin`: rohes Binary
- `fuserunner`: dasselbe mit XTcc-Trailer
- `INSTALL_bas` und `LOADER_bas`: der RESPR-Wert wird aus der Binärgröße berechnet, also nie von Hand eintragen
- `boot`
- `fuserunner.win`: 2 MB QXL.WIN mit boot, fuse_scr und fuserunner; nur, wenn qxltool im PATH liegt

**levels.py bricht den Build ab, wenn eine Bombe unerreichbar ist.** In diesem Fall die Level reparieren und die Prüfung nicht abschwächen.

Wenn die Binärgröße sich ändert, ändert sich auch die RESPR-Zahl in LIESMICH_README.txt (CALL-Zeile, DE und EN).
Bitte nachziehen; aktuell steht dort 90112.

## Testen (ohne echten QL)

```
export TOOLCHAIN=~/toolchain          # emu.sh sucht sonst in ./toolchain
./tools/emu.sh [-DSCHALTER=wert ...]   # baut src/fuse.asm mit vasm, startet sQLux auf Xvfb :9
EMUSPEED=0.6 EMUNTSC=1 ./tools/emu.sh   # langsamerer Core (Anteil vom QL-Takt) bzw. 60-Hz-Timing nachstellen
./tools/key.sh space 0.2               # Taste halten (xdotool-Namen: Up Down Left Right space Return Escape F1..F5 a..z)
./tools/shot.sh name                   # Screenshot -> emu/shots/name.png, dann mit Read ansehen
python3 tools/sound_notes.py           # Töne aus emu/sound.raw (SDL-"disk"-Audio) per FFT auflisten
```
- emu.sh startet nur vasm, nicht die Python-Generatoren. Nach Änderungen an einer `*.py` also zuerst `make.sh` laufen lassen.
- Titel und Menü erscheinen nach etwa 12–14 s. Der Ladebildschirm wartet auf eine Taste.
- Xvfb stirbt gelegentlich. emu.sh startet es bei Bedarf neu.
- Flackern lässt sich im Emulator nicht beurteilen, das muss auf echter Hardware oder dem MiSTer geprüft werden.

Test-Schalter für vasm (`-D...`, alle mit `ifd`/`ifnd` geschützt):

| Schalter | Wirkung |
|---|---|
| `DEBUG=1` | höchste Zahl Frames pro Schleife als Ziffer im HUD (soll 2 bleiben) |
| `STARTRD=n` | Start in Runde n |
| `SCORETEST=n` | ein Leben, vorgegebene Punktzahl (BCD), um die Highscore-Eingabe zu testen |
| `FEWBOMBS=n` | nur die ersten n Bomben, für schnelles Rundenende |
| `NOENEMY` | keine Gegner |
| `BONUSTEST=n` | Bonus erscheint nach 4 s auf Jack (Einerstelle = Typ 0 Leben, 1 Frost, 2 Explosion; 10..12 = Bonus fliegt frei) |
| `CATCHUP=0` | Nachholschritt bei Verzögerung abschalten (zum Vergleich; Standard 1) |
| `CATCHTEST` | zusammen mit `BONUSTEST=1` (Frost): ein Sucher erscheint neben Jack, um das Fangen eingefrorener Gegner zu testen |

Nach Änderungen an der Physik zusätzlich `python3 levels.py` laufen lassen. `preview.py` zeigt die Level als PNG.

## Architektur

- **Positionsunabhängiger Code.** Variablen liegen in einem MT.ALCHP-Heapblock, Basis **A5** (`v_*`-Offsets über `rs`).
  Dazu kommt ein 32K-Hintergrundpuffer. Für Ziele mehr als 32K entfernt gibt es das Makro `LEAX ziel,An`
  (`.lx\@ lea .lx\@(pc),An / add.l #ziel-.lx\@,An`). Das Label muss lokal bleiben, sonst bricht der Gültigkeitsbereich von `.lokal`-Labels.
- **Job-Header:** `bra.w` + `$4AFB` + Name. Der Einsprung für CALL liegt bei Offset 20.
- **Takt:** Die 50-Hz-Pollroutine (MT.LPOLL) zählt `pcount` hoch. Eine Spielschleife dauert 2 Frames (LOOPF=2).
  Die Musik (`music_tick`) läuft im Frame dazwischen.
- **Mode-8-Pixel:** Ein Wort enthält 4 Pixel; für Pixel p: G = Bit 15-2p, Flash = 14-2p, R = 7-2p, B = 6-2p.
  Farben: K0 B1 R2 M3 G4 C5 Y6 W7. Der Bildschirm liegt bei $20000, 128 Byte pro Zeile.
- **Tabellen in gfx.inc** (feste Reihenfolge, der Code nutzt Offsets): clrmask, pixtab, fullw, lmask, rmask, pattab.
  Ganz am Ende steht `hitwin`; neue Tabellen nur dort anhängen.
- **Sprites:** 12×16 Pixel, 4 vorgeschobene Varianten. Jede hat 16 Zeilen × 4 Wörter × (Maske, Daten), also 256 Byte; ein Bild belegt 1 KB.
  Jack: Index = Bild×2 + Richtung.
- **Render:** Sprites werden nach y sortiert, jedes einzeln gelöscht und neu gezeichnet; Überlappungen werden repariert.
  `bomb_refresh` läuft vor `render`. Sprite-Slots: Jack, MAXEN=6 Gegner, ein Bonus-Slot (Typ 4).
- **Hauptschleife:** render → readkeys → `check_hits` → `game_step` (update_jack, update_enemies, update_bonus, check_bombs, check_life).
  `check_hits` prüft also die Positionen, die gerade auf dem Schirm stehen, nicht die frisch berechneten (sonst Tod trotz sichtbarer Lücke).
  Dauerte eine Schleife länger als LOOPF Frames (`v_lag`), läuft `game_step` einmal zusätzlich ohne Render (CATCHUP), höchstens einmal.
  Im Emulator bleibt die Lag-Ziffer selbst bei EMUSPEED=0.6 mit 6 Gegnern bei 2, erst bei 0.3 greift der Ausgleich.
- **Trefferfenster** `hitwin` (gfx.py → gfx.inc): je Gegnertyp dx_min,dx_max,dy_min,dy_max (Gegner − Jack, Pixel), berechnet aus den sichtbaren
  Sprite-Boxen minus HITM=1 px je Seite und auf das alte Fenster (|dx|<8, |dy|<11) begrenzt. Gilt auch für das Fangen eingefrorener Gegner.
  Wer Sprites ändert, bekommt die Fenster automatisch neu; make.sh gibt sie aus.
- **Gegnertypen:** 1 Läufer (wird am Boden zum Flieger), 2 Sucher, 3 Explosion, 5 Hüpfer (ab Runde 5).
- **Physik** in 1/16 Pixel: WALKV 32, JUMPV 190, GRAV 8, SHORTV 40, GLIDEV 14, MAXFALL 96, FASTV 64.
  `body_move` prüft die Kollision mit Plattformen entlang des ganzen Bewegungswegs.
  **levels.py bildet das exakt nach.** Wer die Physik in fuse.asm ändert, muss levels.py mitziehen.
- **Hintergrund-Bytecode** (backdrops.py):

  | Bytes | Bedeutung |
  |---|---|
  | `y<248: y,x0,len,col` | Span |
  | `248 PROFILE x0,n,col,ybot,n×ytop` | Profil |
  | `249` | EDGE |
  | `250 RECT x,y,w,h,col` | Rechteck |
  | `251 COLS x0,n,col,n×(ytop,len)` | Spalten |
  | `255` | Ende |

  `col` = Farbe | Muster<<3. Muster: 0 voll, 1 Schach, 2 Punkte, 3 H-Linien, 4 Fenstergitter, 5 Ziegel, 6 V-Linien, 7 Punkte 12,5 %.
  Alle 9 Hintergründe zusammen sind etwa 28 KB groß. Wird es mehr, leidet der Speicherbedarf und die Ladezeit pro Level (2–3,5 s).
- **Level-Deskriptor** (levels.inc): Typ, Start x/y, Offsets für Plattformen, Bomben, Spawn und Hintergrund, Mond x/y (0 = kein Mond), 4 Ziegelfarben.
  Bomben: x muss ein Vielfaches von 4 sein, höchstens 24 (MAXBOMB).
- **Musik** (music.inc): Paare aus Tonhöhe und Frames; Tonhöhe 0 = Pause, `254,0` = Schleife, `255,0` = Stopp.
  Tonhöhe p ergibt f = 11458,5/(p+9,6) Hz.
- **Ladebildschirm:** RLE-Verfahren, Steuerbyte c<128 bedeutet c+1 Literale, c≥128 bedeutet das nächste Byte (c-125)-mal; entpackt sind es 32768 Byte.
  Das Spiel überspringt MT.DMODE, wenn schon Mode 8 eingestellt ist, und `opench` löscht den Bildschirm nicht.
  Dadurch bleibt ein vom BOOT geladenes Bild stehen.
- **Highscore-Datei `fuse_hi`** (170 Byte):
  - `'FRH3'`, dann lang.w, diff.w, music.w
  - danach 10 Einträge × (Punkte.l BCD, Runde.w, Name 10 Byte); das High-Byte der Runde ist das Leicht-Flag
  - Suchreihenfolge: `fuse_hi` (TK2-Standardverzeichnis), dann win1_, flp1_, mdv1_
  - Speichern: löschen, dann neu öffnen (IO.OPEN D3=2)
  - Bei einer Formatänderung die Magic-Kennung hochzählen
- **Texte:** Das Makro `LQ` legt ein Paar aus deutschem und englischem QDOS-String an, `lstr` wählt nach `v_lang`.
  **Keine Umlaute** in Spieltexten (der Zeichensatz kennt nur ASCII), also ae/oe/ue/ss.

## Fallstricke bei QDOS und dem QL

- **trap #3 zerstört A1.** Zeiger vor dem Aufruf in ein anderes Register retten (siehe `print_centre`, a4).
- IPC-Ton (MT.IPCOM):
  - Start: `$0a,8,0,0,$aa,$aa,p1,p2,gradx(lo,hi),dauer(lo,hi),grady/wrap,rnd/fuzz,1`
  - Stopp: `$0b,0,0,0,0,0,1`
  - Dauereinheit 43,64 µs, das sind 458 pro Frame.
- **KEYROW-Matrix** (Bit = Spalte; geprüft mit sQLux und dem MiSTer-Quelltext keyboard.v):

  | Zeile | Belegung |
  |---|---|
  | row0 | F4 F1 5 F2 F3 F5 4 7 |
  | row1 | Ret Left Up Esc Right \ Space Down |
  | row2 | ] z . c b £ m ' |
  | row3 | [ Caps k s f = g ; |
  | row4 | l 3 h 1 a p d j |
  | row5 | 9 w i Tab r - y o |
  | row6 | 8 2 6 q e 0 t u |
  | row7 | Shift Ctrl Alt x v / n , |
- Joystick CTL2 liefert F1 = links, F2 = runter, F3 = rechts, F4 = hoch, F5 = Feuer. `readkeys` bildet das auf die Cursorbits ab.
- **Tastaturpuffer leeren**, sonst landen im Spiel getippte Tasten später in BASIC ("bad name"):
  MT.INF liefert die Systemvariablen, der Pufferzeiger steht bei +$4C, dann `move.l 8(a0),12(a0)`.
- Beim Kopieren vom PC geht der **QDOS-Dateiheader** verloren, und EXEC meldet "bad parameter".
  Abhilfe: der XTcc-Trailer (sQLux, Q-emuLator, qxltool), INSTALL_bas (SEXEC) oder der CALL-Weg.
- vasm-Eigenheiten:
  - `%` ist kein Modulo; stattdessen `X-(X/10)*10` schreiben.
  - `addq` geht nur bis 8.
  - Kurze Sprünge können außer Reichweite geraten; dann `.w` verwenden.
- Mit 128K meldet das Spiel "out of memory". Es braucht mindestens 256K.

## MiSTer

- Nötig ist ein OS-ROM mit QL-SD-Treiber: https://www.kilgus.net/soft/MiSTer_QL_OS_qlsd109.zip nach /media/fat/QL entpacken.
  Mit dem Standard-ROM meldet `win1_` "not found".
- RAM auf 640K oder mehr stellen. Dann fuserunner.win als HD-Image einbinden, das ROM js_qlsd* oder minerva_*_qlsd* laden und F1/F2 drücken.
- Gamepad 1 kommt als F1–F5 an, Gamepad 2 als Cursortasten und Leertaste. **Die Pad-Knöpfe reicht der Core nicht weiter.**
  Deshalb muss alles mit dem Steuerkreuz bedienbar bleiben:
  - im Menü wählt „rechts“ aus
  - bei der Namenseingabe beendet „rechts“ auf einem leeren Feld die Eingabe

## Konventionen

- Neue Funktionen immer in beiden Sprachen anlegen (LQ-Paar) und in LIESMICH_README.txt **DE und EN** beschreiben.
- Neue Schalter oder Konstanten mit englischem Kommentar am Anfang von fuse.asm eintragen.
- Nach jeder Änderung:
  1. `make.sh`, ohne Fehler und mit Level-Prüfung OK
  2. `emu.sh -DDEBUG=1`; die Lag-Ziffer muss bei 2 bleiben, auch mit 6 Gegnern in späten Runden
  3. Screenshots ansehen
- Den Leicht-Modus, die Musik-Abschaltung und das Speichern der Highscores nicht vergessen. Alle drei hängen an `fuse_hi`.

## Ideen und offene Punkte

- Wirkung der Flacker-Reduktion auf echter Hardware oder dem MiSTer bestätigen
- Erledigt (Okt. 2026): Forum-Feedback QLCore (Spectrum Next/N-GO): Bewegung „nicht die flüssigste“. Mit v1.1 laut Tester
  flüssiger; N-GO läuft mit 50 Hz, Lag-Ziffer im DEBUG-Build immer 2. Offen nur: bei 60-Hz-Timing (NTSC) läuft das Spiel 20 % schneller
- weitere Runden und Hintergründe; das Budget für den Speicher im Auge behalten
- Gegner-Verhalten in Runde 9+ (zweiter Durchlauf) feinjustieren
- Musik während des Spiels ist bewusst weggelassen: der QL hat nur einen Tonkanal, und Effekte haben Vorrang
