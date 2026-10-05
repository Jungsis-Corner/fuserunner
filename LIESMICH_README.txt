FUSE RUNNER - ein Bomben-Sammelspiel fuer den Sinclair QL
==========================================================
(English version below)

Ein Spiel im Stil von Bomb Jack, komplett in 68000-Assembler, Mode 8.
Braucht einen QL mit Speichererweiterung (256K oder mehr; beim MiSTer
RAM auf 640K stellen). Laeuft mit stabilen 25 Bildern/s auf einem QL
mit Original-Geschwindigkeit.

Idee: Jungsi - Code: Claude und Jungsi - www.jungsi.de
Download: https://jungsi.itch.io/fuserunner

DATEIEN
  fuserunner.win  QL-SD/QXL.WIN-Image mit BOOT und Spiel (MiSTer, QPC2,
                  Q-emuLator, QL-SD)
  fuserunner      Spiel mit XTcc-Trailer (sQLux, Q-emuLator: direkt EXEC)
  fuse_scr        Ladebildschirm (32K Bildschirmspeicher), wird vom BOOT
                  vor dem Spiel geladen
  fuse_bin        rohes Binary ohne Dateiheader (fuer LBYTES/CALL)
  INSTALL_bas     erzeugt per SEXEC eine startbare Datei und startet sie
  LOADER_bas      Start ueber RESPR/LBYTES/CALL
  src/            Quelltext und Werkzeuge (siehe BAUEN)

STARTEN
  MiSTer (braucht ein OS-ROM mit QL-SD-Treiber, das Standard-ROM
  kennt kein win1_ und meldet "not found"):
    1. https://www.kilgus.net/soft/MiSTer_QL_OS_qlsd109.zip laden,
       entpacken und alle Dateien nach /media/fat/QL kopieren
    2. fuserunner.win ebenfalls nach /media/fat/QL kopieren
    3. MiSTer starten, den QL-Core waehlen
    4. F12 - RAM auf 640K (oder mehr) stellen
    5. F12 - "Mount HD image": fuserunner.win waehlen
    6. F12 - "Load OS ROM": js_qlsdxxx oder minerva_xxx_qlsdxxx waehlen
    7. F1 oder F2 druecken - das Spiel startet von win1_
  QPC2 / Q-emuLator: fuserunner.win als WIN1 einbinden, dann
  LRUN win1_boot.

  Fehlt der Datei nach dem Kopieren vom PC der QDOS-Header, meldet EXEC
  "bad parameter". Dann INSTALL_bas einmal starten (Laufwerk in Zeile 30
  anpassen) oder per CALL starten:
      a=RESPR(90112):LBYTES win1_fuse_bin,a:CALL a+20

STEUERUNG
  Tastatur:  Cursortasten + Leertaste, ENTER = Pause, ESC = Menue
  Joystick:  CTL1 (wie Cursortasten + Leertaste) oder CTL2 (F1-F5)
  MiSTer:    Das erste Gamepad meldet der QL-Core als F1-F5 (CTL2), das
             zweite als Cursortasten - beide funktionieren. Weil der Core
             die Pad-Knoepfe nicht weiterreicht, geht alles auch nur mit
             dem Steuerkreuz: hoch = springen, im Menue rechts = auswaehlen.
  Springen:  Hoch/Leertaste/Feuer - laenger halten = hoeher,
             im Fallen halten = gleiten, Runter = schnell fallen

LADEBILDSCHIRM
  Der BOOT laedt zuerst den Ladebildschirm (MODE 8: LBYTES win1_fuse_scr,
  131072) und dann das Spiel. Das Spiel zeigt das Bild auch selbst, wenn
  es anders gestartet wird. Weiter zum Menue mit einer beliebigen Taste.

MENUE
  Spiel starten, Anleitung, Highscores, Schwierigkeit (Normal/Leicht),
  Musik (An/Aus - aus heisst: nur Soundeffekte), Sprache (Deutsch ist
  Standard, Englisch umschaltbar), Credits, Ende.
  Auswahl mit hoch/runter, bestaetigen mit Leertaste, ENTER, Feuer oder
  rechts.
  Die Titelmelodie laeuft im Menue; nach 20 Sekunden ohne Eingabe zeigt
  das Menue abwechselnd Highscores und Credits.

SCHWIERIGKEIT
  Normal: 3 Leben. Leicht: 5 Leben, langsamere und weniger Gegner.
  Leicht gespielte Highscores sind in der Tabelle mit L markiert.

SPIELREGELN
  Alle Bomben einsammeln = Runde geschafft. Nach der ersten Bombe brennt
  immer eine (blinkt gelb): 200 statt 100 Punkte, danach entzuendet sich
  die naechste. Am Rundenende gibt es 500 Bonuspunkte fuer jede brennende
  Bombe, die ihr in der Reihenfolge erwischt habt.
  Gegner: gruene Laeufer werden am Boden zu Fliegern, die euch verfolgen.
  Ab Runde 5 kommen gelbe Huepfer dazu, die von Plattform zu Plattform
  auf euch zuspringen.
  Bonus-Gegenstaende (brennende Bomben fuellen den Zaehler doppelt so
  schnell):
    Herz          Extraleben
    Schneeflocke  friert alle Gegner 6 Sekunden ein - eingefrorene Gegner
                  beruehren: 200, 400, 800, 1600, 3200 Punkte
    Stern         alle Gegner explodieren
  Extraleben alle 20000 Punkte (bis 9 Leben). Nach einem verlorenen
  Leben ist Jack 3 Sekunden geschuetzt (er blinkt).
  Neun Runden: Stadt, Berge, Wueste, Hafen, Burg, Wald, Mondbasis (ganz
  ohne Plattformen), Arktis, Vulkan - danach von vorn, schneller und mit
  mehr Gegnern.

HIGHSCORES
  Die Top 10, Sprache, Schwierigkeit und Musik werden in der Datei fuse_hi
  gespeichert (TK2-Standardverzeichnis, sonst win1_, flp1_, mdv1_).
  Namen einfach auf der Tastatur tippen - oder mit Joystick:
  hoch/runter = Buchstabe, rechts/Feuer = weiter, links = zurueck,
  ENTER (oder rechts/Feuer auf einem leeren Feld) = fertig.

MUSIK UND SOUND
  Titelmelodie und kurze Jingles (Rundenstart, Runde geschafft, Spiel
  vorbei, neuer Highscore) ueber den QL-Lautsprecher. Im Spiel selbst
  gibt es nur Soundeffekte, weil der QL nur einen Tonkanal hat.

BAUEN
  In src/: ./make.sh  (braucht vasm und Python 3; fuer fuserunner.win
  zusaetzlich qxltool, als 32-Bit-Programm uebersetzt).
  levels.py prueft bei jedem Bau, ob jede Bombe erreichbar ist,
  preview.py zeichnet alle Level als PNG, music.py enthaelt die Melodien,
  splash.py zeichnet den Ladebildschirm.

----------------------------------------------------------------------

FUSE RUNNER - a bomb collecting game for the Sinclair QL
========================================================

A Bomb Jack style game written entirely in 68000 assembler, Mode 8.
Needs a QL with memory expansion (256K or more; on MiSTer set RAM to
640K). Runs at a steady 25 frames per second at original QL speed.

Idea: Jungsi - Code: Claude and Jungsi - www.jungsi.de
Download: https://jungsi.itch.io/fuserunner

FILES
  fuserunner.win  QL-SD/QXL.WIN image with BOOT and game (MiSTer, QPC2,
                  Q-emuLator, QL-SD)
  fuserunner      game with XTcc trailer (sQLux, Q-emuLator: EXEC directly)
  fuse_scr        loading screen (32K screen memory), loaded by the BOOT
                  file before the game
  fuse_bin        raw binary without file header (for LBYTES/CALL)
  INSTALL_bas     creates an executable file with SEXEC and runs it
  LOADER_bas      starts the game via RESPR/LBYTES/CALL
  src/            source code and tools (see BUILDING)

RUNNING
  MiSTer (needs an OS ROM with the QL-SD driver; the standard ROM does
  not know win1_ and reports "not found"):
    1. download https://www.kilgus.net/soft/MiSTer_QL_OS_qlsd109.zip,
       extract it and copy all files to /media/fat/QL
    2. copy fuserunner.win to /media/fat/QL as well
    3. start the MiSTer, choose the QL core
    4. F12 - set RAM to 640K (or more)
    5. F12 - "Mount HD image": choose fuserunner.win
    6. F12 - "Load OS ROM": choose js_qlsdxxx or minerva_xxx_qlsdxxx
    7. press F1 or F2 - the game starts from win1_
  QPC2 / Q-emuLator: attach fuserunner.win as WIN1, then LRUN win1_boot.

  If the QDOS header got lost while copying from a PC, EXEC reports
  "bad parameter". Run INSTALL_bas once (change the drive in line 30) or
  start via CALL:
      a=RESPR(90112):LBYTES win1_fuse_bin,a:CALL a+20

CONTROLS
  Keyboard:  cursor keys + space, ENTER = pause, ESC = menu
  Joystick:  CTL1 (like cursor keys + space) or CTL2 (F1-F5)
  MiSTer:    the QL core reports the first gamepad as F1-F5 (CTL2) and
             the second as cursor keys - both work. As the core does not
             pass on the pad buttons, everything works with the d-pad
             alone: up = jump, right = select in the menu.
  Jumping:   up/space/fire - hold longer = higher, hold while falling =
             glide, down = drop fast

LOADING SCREEN
  The BOOT file loads the loading screen first (MODE 8: LBYTES
  win1_fuse_scr,131072), then the game. The game also shows the picture
  itself when started another way. Press any key for the menu.

MENU
  Start game, how to play, high scores, difficulty (normal/easy),
  music (on/off - off means sound effects only), language (German is
  the default, English selectable), credits, quit.
  Choose with up/down, confirm with space, ENTER, fire or right.
  The title music plays in the menu; after 20 seconds without input the
  menu shows high scores and credits.

DIFFICULTY
  Normal: 3 lives. Easy: 5 lives, slower and fewer enemies.
  High scores played on easy are marked E in the table.

HOW TO PLAY
  Collect all bombs to clear the round. After the first bomb one bomb is
  always lit (flashing yellow): 200 instead of 100 points, then the next
  one lights up. At the end of the round you get 500 bonus points for
  every lit bomb collected in sequence.
  Enemies: green walkers turn into flyers that chase you once they reach
  the floor. From round 5 yellow hoppers join in and jump from platform to
  platform towards you.
  Bonus items (lit bombs fill the counter twice as fast):
    Heart      extra life
    Snowflake  freezes all enemies for 6 seconds - touch frozen enemies
               for 200, 400, 800, 1600, 3200 points
    Star       all enemies explode
  Extra life every 20000 points (up to 9). After losing a life Jack is
  protected for 3 seconds (he blinks).
  Nine rounds: city, mountains, desert, harbour, castle, forest, moon base
  (no platforms at all), arctic, volcano - then again, faster and with more
  enemies.

HIGH SCORES
  The top 10, language, difficulty and music setting are saved in the file fuse_hi
  (TK2 default directory, otherwise win1_, flp1_, mdv1_).
  Just type your name on the keyboard - or use the joystick:
  up/down = letter, right/fire = next, left = back,
  ENTER (or right/fire on an empty letter) = done.

MUSIC AND SOUND
  Title music and short jingles (round start, round clear, game over, new
  high score) on the QL beeper. During play there are sound effects only,
  as the QL has a single sound channel.

BUILDING
  In src/: ./make.sh  (needs vasm and Python 3; for fuserunner.win also
  qxltool, compiled as a 32-bit program).
  levels.py checks on every build that every bomb can be reached,
  preview.py renders all levels to a PNG, music.py holds the tunes,
  splash.py draws the loading screen.
