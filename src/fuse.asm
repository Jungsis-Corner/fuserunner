;=====================================================================
; FUSE RUNNER - a bomb collecting game for the Sinclair QL
; 68000/68008 assembler, Mode 8 (256x256, 8 colours)
;
; Assembler : vasm  ->  vasmm68k_mot -Fbin -o fuse_bin fuse.asm
; Start     : EXEC_W mdv1_fuserunner        (file with job header)
;        or  a=RESPR(61440):LBYTES mdv1_fuse_bin,a:CALL a+20
;
; The code is position independent (PIC): all variables live in a
; heap block allocated with MT.ALCHP, base register A5.
;=====================================================================

    ifnd DEBUG
DEBUG   equ     0               ; 1 = show max frames per loop in HUD
    endc
SOUND   equ     1               ; 1 = IPC beeps
    ifnd STARTRD
STARTRD equ     1               ; first round (for testing)
    endc
    ifnd CATCHUP
CATCHUP equ     1               ; 1 = extra logic step when a loop took more than LOOPF frames
    endc

;---------------------------------------------------------------------
; Hardware / playfield
;---------------------------------------------------------------------
SCREEN  equ     $20000
LINEB   equ     128             ; bytes per screen line
PF_TOP  equ     16              ; first playfield line (HUD above)
PF_CEIL equ     20              ; first free line below the ceiling
FLOORY  equ     248             ; top of floor
SPRW    equ     12
SPRH    equ     16
XMIN    equ     4
XMAX    equ     252-SPRW
LOOPF   equ     2               ; frames per game loop (25 Hz)
MAXEN   equ     6
NSPR    equ     1+MAXEN+1         ; Jack, enemies, bonus item
MAXBOMB equ     24
BONUSEVERY equ  8               ; bonus points needed (bomb 1, lit bomb 2)
INVT    equ     75              ; protection after a new life (3 s)
MENUN   equ     8               ; menu entries
HSN     equ     10              ; high score entries
HSSIZE  equ     16              ; score.l, round.w, name 10 bytes
HSFILE  equ     4+2+2+2+HSN*HSSIZE ; magic, language, difficulty, music, table
NAMEL   equ     10
FREEZET equ     150             ; freeze time in loops (6 s)
BONUST  equ     250             ; bonus lifetime in loops

; physics in 1/16 pixel per loop
WALKV   equ     32
JUMPV   equ     190
GRAV    equ     8
SHORTV  equ     40
GLIDEV  equ     14
MAXFALL equ     96
FASTV   equ     64

; character width (512 coordinates) for CSIZE 2,0 and 3,1 in Mode 8
CW0     equ     12
CW1     equ     16
TXTX    equ     150             ; x of the bonus lines on the title screen

;---------------------------------------------------------------------
; QDOS
;---------------------------------------------------------------------
MT_FRJOB equ    $05
MT_DMODE equ    $10
MT_IPCOM equ    $11
MT_ALCHP equ    $18
MT_RECHP equ    $19
MT_LPOLL equ    $1c
MT_RPOLL equ    $1d
IO_OPEN  equ    $01
IO_CLOSE equ    $02
IO_SSTRG equ    $07
SD_BORDR equ    $0c
SD_PIXP  equ    $17
SD_CLEAR equ    $20
SD_SETPA equ    $27
SD_SETST equ    $28
SD_SETIN equ    $29
SD_SETSZ equ    $2d

; KEYROW(1) bits - CTL1 joystick = cursor keys + space
K_ENTER equ     0
K_LEFT  equ     1
K_UP    equ     2
K_ESC   equ     3
K_RIGHT equ     4
K_SPACE equ     6
K_DOWN  equ     7
KM_JUMP equ     (1<<K_UP)|(1<<K_SPACE)

;---------------------------------------------------------------------
; Structures
;---------------------------------------------------------------------
        rsreset                 ; sprite / actor
s_act   rs.w    1
s_type  rs.w    1               ; 0 = Jack, 1 = walker, 2 = flyer
s_x     rs.w    1               ; Position in 1/16 px
s_y     rs.w    1
s_vx    rs.w    1
s_vy    rs.w    1
s_gnd   rs.w    1               ; standing on a platform
s_dir   rs.w    1
s_anim  rs.w    1
s_drawn rs.w    1               ; currently visible on screen
s_soff  rs.w    1               ; screen offset of last draw
s_flag  rs.w    1               ; bit 0: hit wall/side
s_img   rs.l    1
s_size  rs.b    0

        rsreset                 ; bomb
b_x     rs.w    1
b_y     rs.w    1
b_state rs.w    1               ; 1 = still there
b_dirty rs.w    1               ; 1 = needs redraw
b_save  rs.l    8               ; background below (2 words x 8 lines)
b_size  rs.b    0

        rsreset                 ; global variables (A5)
v_heap  rs.l    1
v_bg    rs.l    1               ; background buffer (32K, screen layout)
v_sp    rs.l    1
v_mode  rs.w    1               ; 0 = Job, 1 = CALL
v_last  rs.w    1
v_poll  rs.l    2               ; poll list linkage
v_hud   rs.l    1
v_msg   rs.l    1
v_keys  rs.w    1
v_pkeys rs.w    1
v_score rs.l    1               ; BCD
v_ptsb  rs.l    1
v_lives rs.w    1
v_round rs.w    1
v_hudd  rs.w    1
v_rand  rs.l    1
v_plat  rs.l    1
v_spwt  rs.l    1               ; spawn table
v_nb    rs.w    1
v_bleft rs.w    1
v_lit   rs.w    1
v_flash rs.w    1
v_spawn rs.w    1
v_spwi  rs.w    1
v_spwin rs.w    1
v_maxen rs.w    1
v_espd  rs.w    1
v_dead  rs.w    1
v_lag   rs.w    1
v_lagmx rs.w    1
v_dbgc  rs.w    1
v_dbgs  rs.w    1
v_jsx   rs.w    1
v_jsy   rs.w    1
v_moonx rs.w    1
v_moony rs.w    1
v_bc0   rs.w    1               ; brick colours: top, main, mortar, joint
v_bc1   rs.w    1
v_bc2   rs.w    1
v_bc3   rs.w    1
v_bcnt  rs.w    1               ; bombs collected since last bonus
v_freeze rs.w   1               ; enemies frozen while > 0
v_btime rs.w    1               ; bonus lifetime
v_btest rs.w    1
v_fpts  rs.l    1               ; BCD points for the next frozen enemy
v_inv   rs.w    1               ; Jack cannot be hurt while > 0
v_ord   rs.l    NSPR            ; render order (sprite pointers)
v_okey  rs.w    NSPR            ; render order keys (screen line)
v_mptr  rs.l    1               ; music: next note (0 = silent)
v_mloop rs.l    1               ; music: loop start
v_mwait rs.w    1               ; music: frames until the next note
v_beep  rs.b    16              ; IPC sound block for music notes
v_sysv  rs.l    1               ; system variables (MT.INF)
v_krb   rs.b    8               ; IPC block for KEYROW of any row
v_kprev rs.b    8               ; previous key matrix (typing)
v_next  rs.l    1               ; BCD score for the next extra life
v_litc  rs.w    1               ; lit bombs collected this round
v_bonus rs.l    1               ; BCD round bonus
v_lvl   rs.w    1               ; level layout 0..NLEV-1
v_sel   rs.w    1               ; menu selection
v_idle  rs.w    1
v_newhi rs.w    1               ; highlighted high score line (-1 none)
v_hidev rs.w    1               ; device of the high score file (-1 none)
v_rep   rs.w    1               ; key repeat counter
v_npos  rs.w    1
v_name  rs.b    NAMEL+2
v_hsmag rs.l    1               ; --- high score file image (HSFILE bytes)
v_lang  rs.w    1               ; 0 = German, 1 = English
v_diff  rs.w    1               ; 0 = normal, 1 = easy
v_music rs.w    1               ; 0 = music on, 1 = off (effects stay)
v_hs    rs.b    HSN*HSSIZE
v_str   rs.b    40
v_spr   rs.b    s_size*NSPR
v_bombs rs.b    b_size*MAXBOMB
v_size  rs.b    0
LASTSPR equ     v_spr+s_size*MAXEN       ; last enemy
BONUSSPR equ    v_spr+s_size*(MAXEN+1)   ; bonus item

LEAX    macro                   ; PIC lea for targets more than 32K away
.lx\@   lea     .lx\@(pc),\2
        add.l   #\1-.lx\@,\2
        endm

qstr    macro
        dc.w    qe\@-qs\@
qs\@    dc.b    \1
qe\@
        even
        endm

;=====================================================================
; Job header
;=====================================================================
        bra.w   jobentry
        dc.w    0
        dc.w    $4afb
        dc.w    10
        dc.b    'FuseRunner'
        even
callentry:                      ; offset 20: entry point for CALL
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #1,d7
        bra     common
jobentry:
        moveq   #0,d7
common:
        move.l  sp,a4
        moveq   #MT_ALCHP,d0
        move.l  #v_size+32768,d1
        moveq   #-1,d2
        trap    #1
        tst.l   d0
        bne     leave
        move.l  a0,a5
        move.l  a5,a1
        move.w  #v_size/2-1,d0
.clr    clr.w   (a1)+
        dbra    d0,.clr
        move.l  a5,v_heap(a5)
        lea     v_size(a5),a1
        move.l  a1,v_bg(a5)
        move.l  a4,v_sp(a5)
        move.w  d7,v_mode(a5)
        move.l  #$1234567,v_rand(a5)

        moveq   #0,d0           ; MT.INF: where are the system variables?
        trap    #1
        move.l  a0,v_sysv(a5)
        moveq   #MT_DMODE,d0    ; already Mode 8 (loading screen shown by BOOT)?
        moveq   #-1,d1
        moveq   #-1,d2
        trap    #1
        cmp.b   #8,d1
        beq.s   .m8
        moveq   #MT_DMODE,d0    ; Mode 8
        moveq   #8,d1
        moveq   #-1,d2
        trap    #1
.m8

        lea     v_poll(a5),a0   ; 50 Hz counter via poll list
        lea     pollrt(pc),a1
        move.l  a1,4(a0)
        moveq   #MT_LPOLL,d0
        trap    #1

        lea     hudname(pc),a0
        bsr     opench
        move.l  a0,v_hud(a5)
        lea     msgname(pc),a0
        bsr     opench
        move.l  a0,v_msg(a5)

;=====================================================================
; Start: load high scores and language, then the menu
;=====================================================================
        bsr     hs_load
        bsr     splash_show
        clr.w   v_sel(a5)

;=====================================================================
; Menu (joystick / cursor keys + space)
;=====================================================================
menu:
        move.w  #-1,v_newhi(a5)
        LEAX    mus_title,a0    ; title music (unless it is already playing)
        tst.l   v_mptr(a5)
        beq.s   .mp
        cmp.l   v_mloop(a5),a0
        beq.s   .mq
.mp     bsr     music_play
.mq
        bsr     page_clear
        lea     mn_title(pc),a2
        bsr     print_table
        bsr     menu_hiline
        moveq   #0,d4
.it     bsr     menu_item
        addq.w  #1,d4
        cmp.w   #MENUN,d4
        bne.s   .it
        clr.w   v_idle(a5)
        bsr     menu_marker
        bsr     keys_release
.loop   bsr     frame1
        bsr     readkeys
        move.w  v_pkeys(a5),d1
        not.w   d1
        and.w   d0,d1           ; d1 = newly pressed
        addq.w  #1,v_idle(a5)
        btst    #K_UP,d1
        beq.s   .nu
        move.w  v_sel(a5),d4
        subq.w  #1,v_sel(a5)
        bpl.s   .mv
        move.w  #MENUN-1,v_sel(a5)
        bra.s   .mv
.nu     btst    #K_DOWN,d1
        beq.s   .nd
        move.w  v_sel(a5),d4
        addq.w  #1,v_sel(a5)
        cmp.w   #MENUN,v_sel(a5)
        blo.s   .mv
        clr.w   v_sel(a5)
.mv     bsr     menu_item       ; old entry back to normal colour
        move.w  v_sel(a5),d4
        bsr     menu_item
        bsr     menu_marker
        clr.w   v_idle(a5)
        bra.s   .loop
.nd     btst    #K_ESC,d1
        bne     exit_prog
        and.w   #(1<<K_SPACE)|(1<<K_ENTER)|(1<<K_RIGHT),d1
        bne.s   .sel
        move.w  v_idle(a5),d0
        and.w   #7,d0
        bne.s   .na
        bsr     menu_marker     ; little walk animation
.na     cmp.w   #50*20,v_idle(a5)
        blo.s   .loop
        ; attract mode: high scores, credits, back to the menu
        bsr     page_scores
        move.w  #50*10,d7
        bsr     waitkey
        bne     menu
        bsr     page_credits
        move.w  #50*10,d7
        bsr     waitkey
        bra     menu
.sel    move.w  v_sel(a5),d0
        beq     newgame
        subq.w  #1,d0
        bne.s   .s2
        bsr     page_help
        bra.s   .wm
.s2     subq.w  #1,d0
        bne.s   .s3
        bsr     page_scores
        bra.s   .wm
.s3     subq.w  #1,d0
        bne.s   .s4
        eor.w   #1,v_diff(a5)   ; difficulty, remembered in the file
        bsr     hs_save
        bra     menu
.s4     subq.w  #1,d0
        bne.s   .s4b
        eor.w   #1,v_music(a5)  ; music on/off, remembered in the file
        bsr     music_stop
        bsr     hs_save
        bra     menu
.s4b    subq.w  #1,d0
        bne.s   .s5
        eor.w   #1,v_lang(a5)   ; language, remembered in the file
        bsr     hs_save
        bra     menu
.s5     subq.w  #1,d0
        bne     exit_prog
        bsr     page_credits
.wm     moveq   #0,d7
        bsr     waitkey
        bra     menu

menu_item:                      ; d4 = entry: print it (yellow if selected)
        movem.l d0-d7/a0-a3,-(sp)
        lea     mn_items(pc),a1
        move.w  d4,d0
        bsr     pair_n
        cmp.w   #3,d4
        bne.s   .nd
        tst.w   v_diff(a5)
        beq.s   .ne
        lea     mn_easy(pc),a1
        bra.s   .ne
.nd     cmp.w   #4,d4
        bne.s   .ne
        tst.w   v_music(a5)
        beq.s   .ne
        lea     mn_moff(pc),a1
.ne
        moveq   #5,d5
        cmp.w   v_sel(a5),d4
        bne.s   .c
        moveq   #6,d5
.c      move.w  d4,d0
        mulu    #15,d0
        add.w   #90,d0
        move.w  d0,d4
        moveq   #0,d6
        bsr     printl
        movem.l (sp)+,d0-d7/a0-a3
        rts

menu_marker:                    ; Jack walks next to the selected entry
        movem.l d0-d7/a0-a3,-(sp)
        lea     BONUSSPR(a5),a0
        bsr     erase_spr
        move.w  #44<<4,s_x(a0)
        move.w  v_sel(a5),d0
        mulu    #15,d0
        add.w   #90+20+5-9,d0
        lsl.w   #4,d0
        move.w  d0,s_y(a0)
        addq.w  #1,s_anim(a0)
        move.w  s_anim(a0),d0
        and.w   #1,d0
        addq.w  #1,d0           ; walk frames 1/2, facing right
        lsl.w   #8,d0
        lsl.w   #3,d0           ; * 2048 (frame * 2 directions * 1 KB)
        LEAX    spr_jack,a1
        add.w   d0,a1
        move.l  a1,s_img(a0)
        bsr     draw_spr
        movem.l (sp)+,d0-d7/a0-a3
        rts

menu_hiline:                    ; "HIGHSCORE 012345 NAME"
        lea     v_str(a5),a0
        lea     mn_hi(pc),a1
        bsr     lstr
        move.w  (a1)+,d1
        addq.l  #2,a0
        subq.w  #1,d1
.c      move.b  (a1)+,(a0)+
        dbra    d1,.c
        lea     v_hs(a5),a1
        bsr     put_score
        move.b  #' ',(a0)+
        lea     6(a1),a2
        moveq   #NAMEL-1,d1
.n      move.b  (a2)+,(a0)+
        dbra    d1,.n
        bsr     str_close
        lea     v_str(a5),a1
        moveq   #66,d4
        moveq   #7,d5
        moveq   #0,d6
        bra     print_centre

;---------------------------------------------------------------------
; Loading screen: unpack the RLE picture, wait for a key
;---------------------------------------------------------------------
SPL_Y   equ     220             ; screen line of the "press a key" text

splash_show:
        move.l  v_bg(a5),a1     ; unpack into the background buffer
        move.l  a1,a3
        add.l   #32768,a3
        LEAX    splash,a0
.u      moveq   #0,d0
        move.b  (a0)+,d0
        cmp.b   #128,d0
        bhs.s   .rp
.lt     move.b  (a0)+,(a1)+     ; c < 128: c+1 literal bytes
        dbra    d0,.lt
        bra.s   .ck
.rp     sub.w   #126,d0         ; c >= 128: next byte c-125 times
        move.b  (a0)+,d1
.rr     move.b  d1,(a1)+
        dbra    d0,.rr
.ck     cmp.l   a3,a1
        blo.s   .u
        move.l  v_bg(a5),a0     ; whole picture to the screen
        lea     SCREEN,a1
        move.w  #8192-1,d0
.cp     move.l  (a0)+,(a1)+
        dbra    d0,.cp
        LEAX    mus_title,a0
        bsr     music_play
        bsr     keys_release
        clr.w   v_idle(a5)
.l      bsr     frame1
        move.w  v_idle(a5),d0
        and.w   #31,d0
        bne.s   .k
        btst    #5,v_idle+1(a5) ; blink: text on / picture back
        bne.s   .off
        lea     s_key(pc),a1
        move.w  #SPL_Y-20,d4
        moveq   #6,d5
        moveq   #0,d6
        bsr     printl
        bra.s   .k
.off    move.l  v_bg(a5),a0
        lea     SPL_Y*LINEB(a0),a0
        lea     SCREEN+SPL_Y*LINEB,a1
        move.w  #10*LINEB/4-1,d0
.rs     move.l  (a0)+,(a1)+
        dbra    d0,.rs
.k      addq.w  #1,v_idle(a5)
        bsr     readkeys
        tst.w   d0
        beq.s   .l
        rts

;---------------------------------------------------------------------
; Pages
;---------------------------------------------------------------------
page_clear:
        bsr     cls_all
        lea     BONUSSPR(a5),a0
        clr.w   s_drawn(a0)
        move.l  v_hud(a5),a0
        moveq   #SD_CLEAR,d0
        bsr     io3
        move.l  v_msg(a5),a0
        moveq   #SD_CLEAR,d0
        bsr     io3
        movem.l d0-d7/a4,-(sp)  ; brick frame top and bottom
        move.l  v_bg(a5),a4
        move.w  #6,v_bc0(a5)
        move.w  #2,v_bc1(a5)
        move.w  #3,v_bc2(a5)
        clr.w   v_bc3(a5)
        moveq   #0,d0
        moveq   #PF_TOP,d1
        move.w  #256,d6
        moveq   #PF_CEIL-PF_TOP,d7
        bsr     drawbrick
        move.w  #FLOORY,d1
        moveq   #8,d7
        bsr     drawbrick
        bsr     restore_pf
        movem.l (sp)+,d0-d7/a4
        rts

page_help:
        bsr     page_clear
        lea     pg_help(pc),a2
        bsr     print_table
        moveq   #0,d4           ; bonus icons next to their lines
.ic     lea     BONUSSPR(a5),a0
        move.w  d4,s_dir(a0)
        clr.w   s_anim(a0)
        move.w  #(TXTX/2-20)<<4,s_x(a0)
        move.w  d4,d0
        add.w   d0,d0
        lea     iconys(pc),a1
        move.w  0(a1,d0.w),d0
        add.w   #20+5-8,d0
        lsl.w   #4,d0
        move.w  d0,s_y(a0)
        bsr     bonus_img
        bsr     draw_spr
        addq.w  #1,d4
        cmp.w   #3,d4
        bne.s   .ic
        lea     BONUSSPR(a5),a0
        clr.w   s_drawn(a0)
        rts

page_credits:
        bsr     page_clear
        lea     pg_cred(pc),a2
        bsr     print_table
        lea     BONUSSPR(a5),a0 ; a few actors as decoration
        move.w  #40<<4,s_x(a0)
        move.w  #(20+96)<<4,s_y(a0)
        LEAX    spr_jack+3*2048,a1
        move.l  a1,s_img(a0)
        bsr     draw_spr
        move.w  #204<<4,s_x(a0)
        LEAX    spr_walk,a1
        move.l  a1,s_img(a0)
        bsr     draw_spr
        move.w  #40<<4,s_x(a0)
        move.w  #(20+136)<<4,s_y(a0)
        LEAX    spr_bonus,a1
        move.l  a1,s_img(a0)
        bsr     draw_spr
        move.w  #204<<4,s_x(a0)
        LEAX    spr_seek,a1
        move.l  a1,s_img(a0)
        bsr     draw_spr
        clr.w   s_drawn(a0)
        rts

page_scores:
        bsr     page_clear
        lea     pg_scores(pc),a2
        bsr     print_table
        moveq   #0,d4
.l      bsr     hs_line
        moveq   #7,d5
        cmp.w   #3,d4
        bhs.s   .w
        moveq   #6,d5           ; top three in yellow
.w      cmp.w   v_newhi(a5),d4
        bne.s   .p
        moveq   #4,d5           ; the new entry in green
.p      move.w  d4,d0
        mulu    #15,d0
        add.w   #52,d0
        move.l  d4,-(sp)
        move.w  d0,d4
        lea     v_str(a5),a1
        moveq   #0,d6
        bsr     print_centre
        move.l  (sp)+,d4
        addq.w  #1,d4
        cmp.w   #HSN,d4
        bne.s   .l
        rts

hs_line:                        ; d4 = entry -> v_str "01  012345  NAME        R05"
        movem.l d0-d2/a0-a2,-(sp)
        lea     v_str+2(a5),a0
        moveq   #0,d0
        move.w  d4,d0
        addq.w  #1,d0
        bsr     put_2dig
        move.b  #' ',(a0)+
        move.b  #' ',(a0)+
        move.w  d4,d0
        lsl.w   #4,d0
        lea     v_hs(a5),a1
        add.w   d0,a1
        bsr     put_score
        move.b  #' ',(a0)+
        move.b  #' ',(a0)+
        lea     6(a1),a2
        moveq   #NAMEL-1,d1
.n      move.b  (a2)+,(a0)+
        dbra    d1,.n
        move.b  #' ',(a0)+
        move.b  #' ',(a0)+
        move.b  #'R',(a0)+
        moveq   #0,d0
        move.b  5(a1),d0
        bsr     put_2dig
        move.b  #' ',(a0)+
        move.b  #' ',(a0)+
        tst.b   4(a1)
        beq.s   .nm
        move.b  #'L',-1(a0)     ; L = leicht / easy
        tst.w   v_lang(a5)
        beq.s   .nm
        move.b  #'E',-1(a0)
.nm     bsr     str_close
        movem.l (sp)+,d0-d2/a0-a2
        rts

;---------------------------------------------------------------------
; Text helpers
;---------------------------------------------------------------------
lstr:                           ; a1 = German/English pair -> a1 = string of v_lang
        tst.w   v_lang(a5)
        beq.s   .e
        move.l  d0,-(sp)
        move.w  (a1),d0
        addq.w  #3,d0
        and.w   #$fffe,d0
        add.w   d0,a1
        move.l  (sp)+,d0
.e      rts

pair_n:                         ; a1 = first pair, d0 = n -> a1 = pair n
        subq.w  #1,d0
        bmi.s   .e
.l      bsr.s   skip_pair
        dbra    d0,.l
.e      rts

skip_pair:
        bsr      skip_q
skip_q: move.l  d1,-(sp)
        move.w  (a1),d1
        addq.w  #3,d1
        and.w   #$fffe,d1
        add.w   d1,a1
        move.l  (sp)+,d1
        rts

printl: bsr.s   lstr            ; print pair a1 centred (d4 y, d5 ink, d6 size)
        bra     print_centre

print_table:                    ; a2 = table of y,ink,size,pair ... y=-1
.l      move.w  (a2)+,d4
        bmi.s   .e
        move.w  (a2)+,d5
        move.w  (a2)+,d6
        move.l  a2,a1
        bsr     printl
        move.l  a2,a1
        bsr.s   skip_pair
        move.l  a1,a2
        bra.s   .l
.e      rts

put_score:                      ; a1 = BCD long -> 6 digits at (a0)+
        movem.l d0-d2/a1,-(sp)
        addq.l  #1,a1
        moveq   #2,d1
.d      move.b  (a1)+,d0
        move.b  d0,d2
        lsr.b   #4,d2
        add.b   #'0',d2
        move.b  d2,(a0)+
        and.b   #$0f,d0
        add.b   #'0',d0
        move.b  d0,(a0)+
        dbra    d1,.d
        movem.l (sp)+,d0-d2/a1
        rts

put_2dig:                       ; d0.l = 0..99 -> two digits at (a0)+
        divu    #10,d0
        add.b   #'0',d0
        move.b  d0,(a0)+
        swap    d0
        add.b   #'0',d0
        move.b  d0,(a0)+
        rts

str_close:                      ; a0 = end of text in v_str: set length word
        move.l  a0,d0
        lea     v_str+2(a5),a0
        sub.l   a0,d0
        move.w  d0,-2(a0)
        rts

keys_release:                   ; wait until no key of KEYROW(1) is held
.l      bsr     frame1
        bsr     readkeys
        tst.w   d0
        bne.s   .l
        rts

waitkey:                        ; d7 = timeout in frames (0 = none) -> NE = key
        bsr.s   keys_release
.l      bsr     frame1
        bsr     readkeys
        tst.w   d0
        bne.s   .k
        tst.w   d7
        beq.s   .l
        subq.w  #1,d7
        bne.s   .l
        moveq   #0,d0
        rts
.k      moveq   #1,d0
        rts

;---------------------------------------------------------------------
; High scores: file fuse_hi (TK2 default directory, win1_, flp1_, mdv1_)
;---------------------------------------------------------------------
hs_load:
        lea     hs_default(pc),a0 ; defaults first
        lea     v_hsmag(a5),a1
        move.w  #HSFILE-1,d0
.cp     move.b  (a0)+,(a1)+
        dbra    d0,.cp
        move.w  #-1,v_hidev(a5)
        moveq   #0,d4
.dev    bsr     hs_name         ; a0 = file name of device d4
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #1,d3           ; old file, shared
        trap    #2
        tst.l   d0
        bne.s   .nx
        move.l  a0,a4
        moveq   #3,d0           ; IO.FSTRG
        move.w  #HSFILE,d2
        moveq   #-1,d3
        lea     v_name(a5),a1   ; read into a scratch area first
        lea     v_bombs(a5),a1
        trap    #3
        move.l  d1,d5
        move.l  a4,a0
        moveq   #IO_CLOSE,d0
        trap    #2
        move.w  d4,v_hidev(a5)
        cmp.w   #HSFILE,d5
        bne.s   .e
        lea     v_bombs(a5),a0
        cmp.l   #'FRH3',(a0)
        bne.s   .e
        lea     v_hsmag(a5),a1
        move.w  #HSFILE-1,d0
.c2     move.b  (a0)+,(a1)+
        dbra    d0,.c2
.e      rts
.nx     addq.w  #1,d4
        cmp.w   #4,d4
        bne.s   .dev
        rts

hs_save:                        ; known device first, then all of them
        move.w  v_hidev(a5),d4
        bmi.s   .all
        bsr.s   hs_write
        beq.s   .e
.all    moveq   #0,d4
.l      bsr.s   hs_write
        beq.s   .ok
        addq.w  #1,d4
        cmp.w   #4,d4
        bne.s   .l
        rts
.ok     move.w  d4,v_hidev(a5)
.e      rts

hs_write:                       ; d4 = device -> EQ = saved
        movem.l d1-d4/a0-a4,-(sp)
        bsr.s   hs_name
        move.l  a0,a4
        moveq   #4,d0           ; IO.DELET (error ignored)
        moveq   #-1,d1
        trap    #2
        move.l  a4,a0
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #2,d3           ; new file
        trap    #2
        tst.l   d0
        bne.s   .e
        move.l  a0,a4
        moveq   #IO_SSTRG,d0
        move.w  #HSFILE,d2
        moveq   #-1,d3
        lea     v_hsmag(a5),a1
        trap    #3
        move.l  d0,d2
        move.l  a4,a0
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  d2,d0
.e      movem.l (sp)+,d1-d4/a0-a4
        tst.l   d0
        rts

hs_name:                        ; d4 = device index -> a0 = QDOS file name
        lea     hs_names(pc),a0
        move.w  d4,d0
        subq.w  #1,d0
        bmi.s   .e
.l      move.w  (a0),d1
        addq.w  #3,d1
        and.w   #$fffe,d1
        add.w   d1,a0
        dbra    d0,.l
.e      rts

hs_check:                       ; after game over: insert score, ask for the name
        lea     v_hs(a5),a1
        moveq   #0,d4
.f      move.l  v_score(a5),d0
        cmp.l   (a1),d0
        bhi.s   .ins
        lea     HSSIZE(a1),a1
        addq.w  #1,d4
        cmp.w   #HSN,d4
        bne.s   .f
        rts                     ; not good enough
.ins    lea     v_hs+(HSN-1)*HSSIZE(a5),a0 ; move the lower entries down
        move.w  #HSN-1,d0
        sub.w   d4,d0
        mulu    #HSSIZE,d0
        bra.s   .mt
.mv     move.b  -1(a0),HSSIZE-1(a0)
        subq.l  #1,a0
.mt     dbra    d0,.mv
        move.l  v_score(a5),(a1)
        move.w  v_round(a5),d0
        tst.w   v_diff(a5)
        beq.s   .rn
        or.w    #$100,d0        ; mark: played on easy
.rn     move.w  d0,4(a1)
        move.w  d4,v_newhi(a5)
        LEAX    mus_hisc,a0
        bsr     music_play
        bsr     enter_name
        lea     v_name(a5),a0
        lea     6(a1),a2
        moveq   #NAMEL-1,d0
.cn     move.b  (a0)+,(a2)+
        dbra    d0,.cn
        bsr     hs_save
        bsr     page_scores
        move.w  #50*15,d7
        bra     waitkey

enter_name:                     ; letter wheel, works with joystick and keys
        movem.l d0-d7/a0-a3,-(sp)
        bsr     page_clear
        lea     pg_name(pc),a2
        bsr     print_table
        lea     v_str(a5),a0    ; "PLATZ 05  011500"
        lea     s_rank(pc),a1
        bsr     lstr
        move.w  (a1)+,d1
        addq.l  #2,a0
        subq.w  #1,d1
.rk     move.b  (a1)+,(a0)+
        dbra    d1,.rk
        moveq   #0,d0
        move.w  v_newhi(a5),d0
        addq.w  #1,d0
        bsr     put_2dig
        move.b  #' ',(a0)+
        move.b  #'-',(a0)+
        move.b  #' ',(a0)+
        lea     v_score(a5),a1
        bsr     put_score
        bsr     str_close
        lea     v_str(a5),a1
        moveq   #80,d4
        moveq   #4,d5
        moveq   #0,d6
        bsr     print_centre
        lea     v_name(a5),a0
        moveq   #NAMEL-1,d0
.bl     move.b  #' ',(a0)+
        dbra    d0,.bl
        clr.w   v_npos(a5)
        bsr     keys_release
        bsr     scan_typed      ; remember keys already held
        clr.w   v_idle(a5)
.draw   bsr     name_show
.loop   bsr     frame1
        addq.w  #1,v_idle(a5)
        move.w  v_idle(a5),d0
        and.w   #15,d0
        beq.s   .draw           ; blink the current letter
        bsr     scan_typed      ; letter or digit typed on the keyboard?
        tst.b   d3
        beq.s   .nt
        lea     v_name(a5),a0
        add.w   v_npos(a5),a0
        move.b  d3,(a0)
        cmp.w   #NAMEL-1,v_npos(a5)
        bhs     .draw
        addq.w  #1,v_npos(a5)
        bra     .draw
.nt     bsr     readkeys
        move.w  v_pkeys(a5),d1
        not.w   d1
        and.w   d0,d1           ; newly pressed
        move.w  d0,d2
        and.w   #(1<<K_UP)|(1<<K_DOWN),d2
        beq.s   .nr
        tst.w   d1              ; held: repeat after a short delay
        bne.s   .first
        addq.w  #1,v_rep(a5)
        cmp.w   #14,v_rep(a5)
        blo.s   .nr
        move.w  #10,v_rep(a5)
        move.w  d2,d1
        bra.s   .ud
.first  clr.w   v_rep(a5)
.ud     lea     v_name(a5),a0
        add.w   v_npos(a5),a0
        bsr     char_index      ; d3 = index of (a0) in the letter set
        btst    #K_UP,d1
        beq.s   .dn
        addq.w  #1,d3
        cmp.w   #CHARN,d3
        blo.s   .st
        moveq   #0,d3
        bra.s   .st
.dn     btst    #K_DOWN,d1
        beq.s   .nr
        subq.w  #1,d3
        bpl.s   .st
        moveq   #CHARN-1,d3
.st     lea     charset(pc),a1
        move.b  0(a1,d3.w),(a0)
        bra      .draw
.nr     btst    #K_LEFT,d1
        beq.s   .nl
        tst.w   v_npos(a5)
        beq      .loop
        subq.w  #1,v_npos(a5)
        bra      .draw
.nl     btst    #K_ENTER,d1
        bne.s   .done
        btst    #K_ESC,d1
        bne.s   .done
        move.w  d1,d2
        and.w   #(1<<K_RIGHT)|(1<<K_SPACE),d2
        beq     .loop
        lea     v_name(a5),a0   ; fire/right on an empty letter = finished
        add.w   v_npos(a5),a0
        cmp.b   #' ',(a0)
        bne.s   .nx
        tst.w   v_npos(a5)
        bne.s   .done
.nx     cmp.w   #NAMEL-1,v_npos(a5)
        bhs.s   .done
        addq.w  #1,v_npos(a5)
        bra     .draw
.done   lea     v_name(a5),a0   ; empty name -> ???
        moveq   #NAMEL-1,d0
.e1     cmp.b   #' ',(a0)+
        dbne    d0,.e1
        bne.s   .ok
        lea     v_name(a5),a0
        move.b  #'?',(a0)+
        move.b  #'?',(a0)+
        move.b  #'?',(a0)+
.ok     movem.l (sp)+,d0-d7/a0-a3
        rts

name_show:                      ; name in big letters, current one blinking
        movem.l d0-d7/a0-a4,-(sp)
        lea     v_str(a5),a0
        move.w  #NAMEL,(a0)+
        lea     v_name(a5),a1
        moveq   #NAMEL-1,d0
.c      move.b  (a1)+,(a0)+
        dbra    d0,.c
        lea     v_str(a5),a1
        moveq   #120,d4
        moveq   #7,d5
        moveq   #1,d6
        bsr     print_centre
        lea     v_str+2(a5),a0  ; cursor line: '_' under the current letter
        moveq   #NAMEL-1,d0
.u      move.b  #' ',(a0)+
        dbra    d0,.u
        lea     v_str+2(a5),a0
        add.w   v_npos(a5),a0
        move.b  #'_',(a0)
        lea     v_str(a5),a1
        move.w  #142,d4
        moveq   #6,d5
        moveq   #1,d6
        bsr     print_centre
        lea     v_str(a5),a0    ; (v_str is reused below)
        move.w  #NAMEL,(a0)
        ; current letter on its own: yellow, or '_' while blinking
        lea     v_str(a5),a0
        move.w  #1,(a0)+
        lea     v_name(a5),a1
        add.w   v_npos(a5),a1
        move.b  (a1),d0
        btst    #3,v_idle+1(a5)
        beq.s   .y
        cmp.b   #' ',d0
        bne.s   .y
        moveq   #'_',d0
.y      move.b  d0,(a0)
        move.l  v_msg(a5),a0
        moveq   #SD_SETSZ,d0
        moveq   #3,d1
        moveq   #1,d2
        bsr     io3
        moveq   #SD_SETIN,d0
        moveq   #6,d1
        bsr     io3
        moveq   #SD_PIXP,d0
        move.w  v_npos(a5),d1
        lsl.w   #4,d1
        add.w   #(512-NAMEL*CW1)/2,d1
        moveq   #120,d2
        bsr     io3
        moveq   #IO_SSTRG,d0
        moveq   #1,d2
        lea     v_str+2(a5),a1
        bsr     io3
        movem.l (sp)+,d0-d7/a0-a4
        rts

scan_typed:                     ; -> d3.b = character of a newly pressed key (0 = none)
        movem.l d0-d2/d4-d6/a0-a3,-(sp)
        moveq   #0,d3
        moveq   #0,d6           ; matrix row
.r      cmp.w   #1,d6           ; row 1 (cursor keys, space, enter) is handled elsewhere
        beq.s   .nx
        lea     v_krb(a5),a3
        move.b  #9,(a3)
        move.b  #1,1(a3)
        clr.l   2(a3)
        move.b  d6,6(a3)
        move.b  #2,7(a3)
        moveq   #MT_IPCOM,d0
        trap    #1
        lea     v_kprev(a5),a0
        move.b  0(a0,d6.w),d2
        move.b  d1,0(a0,d6.w)
        not.b   d2
        and.b   d1,d2           ; bits that became set
        beq.s   .nx
        moveq   #0,d4
.b      btst    d4,d2
        bne.s   .f
        addq.w  #1,d4
        bra.s   .b
.f      move.w  d6,d0
        lsl.w   #3,d0
        add.w   d4,d0
        lea     ktab(pc),a1
        tst.b   d3
        bne.s   .nx
        move.b  0(a1,d0.w),d3
.nx     addq.w  #1,d6
        cmp.w   #8,d6
        bne.s   .r
        movem.l (sp)+,d0-d2/d4-d6/a0-a3
        rts

char_index:                     ; (a0) -> d3 index in charset (0 if unknown)
        lea     charset(pc),a1
        moveq   #0,d3
.l      move.b  0(a1,d3.w),d0
        cmp.b   (a0),d0
        beq.s   .e
        addq.w  #1,d3
        cmp.w   #CHARN,d3
        blo.s   .l
        moveq   #0,d3
.e      rts

;=====================================================================
; Game flow
;=====================================================================
newgame:
        move.w  pcount(pc),d0   ; mix random seed
        add.w   d0,v_rand+2(a5)
        clr.l   v_score(a5)
        move.l  #$20000,v_next(a5)
        move.w  #3,v_lives(a5)
        tst.w   v_diff(a5)
        beq.s   .nl
        move.w  #5,v_lives(a5)  ; easy: five lives
.nl     move.w  #STARTRD,v_round(a5)
        ifd     SCORETEST       ; test build: one life, preset score
        move.l  #SCORETEST,v_score(a5)
        move.w  #1,v_lives(a5)
        endc
newround:
        bsr     music_stop
        bsr     page_clear
        bsr     hud_draw
        bsr     build_round
        lea     v_str(a5),a1    ; show "ROUND nn" while the level is built
        moveq   #70,d4
        moveq   #6,d5
        moveq   #1,d6
        bsr     print_centre
        bsr     setup_level
        lea     v_str(a5),a1
        moveq   #70,d4
        moveq   #6,d5
        moveq   #1,d6
        bsr     print_centre
        lea     lvlnames(pc),a1 ; name of the layout
        move.w  v_lvl(a5),d0
        bsr     pair_n
        moveq   #98,d4
        moveq   #5,d5
        moveq   #0,d6
        bsr     printl
        lea     s_ready(pc),a1
        moveq   #120,d4
        moveq   #7,d5
        moveq   #0,d6
        bsr     printl
        LEAX    mus_start,a0
        bsr     music_play
        moveq   #70,d7
        bsr     delay
        clr.l   v_mptr(a5)
        bsr     restore_pf
newlife:
        bsr     init_actors
        move.w  pcount(pc),v_last(a5)
mainloop:
        bsr     waitloop
        bsr     bomb_refresh
        bsr     render
        bsr     readkeys
        btst    #K_ESC,d0
        bne     to_title
        move.w  v_pkeys(a5),d1
        not.w   d1
        and.w   d0,d1
        btst    #K_ENTER,d1
        beq.s   .np
        bsr     pause
.np     bsr     check_hits      ; on the positions just shown on screen
        tst.w   v_dead(a5)
        bne     .st
        bsr     game_step
        ifne    CATCHUP
        cmp.w   #LOOPF,v_lag(a5) ; loop took longer: one extra logic step
        bls     .st
        tst.w   v_bleft(a5)
        beq     .st
        bsr     check_hits
        tst.w   v_dead(a5)
        bne     .st
        move.w  v_keys(a5),v_pkeys(a5) ; no second jump edge
        bsr     game_step
        endc
.st
        ifne    DEBUG
        bsr     dbg_lag
        endc
        tst.w   v_hudd(a5)
        beq     .nh
        bsr     hud_draw
.nh     tst.w   v_dead(a5)
        bne     died
        tst.w   v_bleft(a5)
        beq     roundclear
        bra     mainloop

game_step:                      ; one step of game logic (25 Hz)
        bsr     update_jack
        bsr     update_enemies
        bsr     update_bonus
        bsr     check_bombs
        bra     check_life

pause:                        ; ENTER pauses, ENTER again continues
        movem.l d0-d7/a0-a3,-(sp)
        lea     s_pause(pc),a1
        moveq   #100,d4
        moveq   #7,d5
        moveq   #1,d6
        bsr     printl
        bsr     keys_release
.l      bsr     frame1
        bsr     readkeys
        btst    #K_ENTER,d0
        beq.s   .l
        bsr     keys_release
        bsr     restore_pf
        move.w  pcount(pc),v_last(a5)
        movem.l (sp)+,d0-d7/a0-a3
        rts

check_life:                     ; extra life every 20000 points
        move.l  v_score(a5),d0
        cmp.l   v_next(a5),d0
        blo.s   .e
        move.l  #$20000,v_ptsb(a5)
        lea     v_ptsb+4(a5),a0
        lea     v_next+4(a5),a1
        move    #4,ccr
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        cmp.w   #9,v_lives(a5)
        bhs.s   .e
        addq.w  #1,v_lives(a5)
        move.w  #1,v_hudd(a5)
        ifne    SOUND
        lea     snd_life(pc),a3
        bsr     ipc
        endc
.e      rts

died:
        ifne    SOUND
        lea     snd_die(pc),a3
        bsr     ipc
        endc
        lea     s_ouch(pc),a1
        moveq   #100,d4
        moveq   #2,d5
        moveq   #1,d6
        bsr     printl
        moveq   #50,d7
        bsr     delay
        bsr     erase_all
        bsr     restore_pf
        subq.w  #1,v_lives(a5)
        bsr     hud_draw
        tst.w   v_lives(a5)
        bne     newlife
        lea     s_over(pc),a1
        moveq   #100,d4
        moveq   #2,d5
        moveq   #1,d6
        bsr     printl
        LEAX    mus_over,a0
        bsr     music_play
        move.w  #100,d7
        bsr     delay
        bsr     hs_check
        bra     menu

roundclear:
        bsr     erase_all
        bsr     bomb_refresh
        clr.l   v_bonus(a5)     ; bonus: 500 for every lit bomb in sequence
        move.w  v_litc(a5),d7
        bra.s   .bt
.bl     move.l  #$500,v_ptsb(a5)
        lea     v_ptsb+4(a5),a0
        lea     v_bonus+4(a5),a1
        move    #4,ccr
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
.bt     dbra    d7,.bl
        move.l  v_bonus(a5),d0
        bsr     add_score
        bsr     hud_draw
        LEAX    mus_clear,a0
        bsr     music_play
        lea     s_clear(pc),a1
        moveq   #80,d4
        moveq   #5,d5
        moveq   #1,d6
        bsr     printl
        lea     v_str(a5),a0    ; "FEUERBOMBEN: nn"
        lea     s_litb(pc),a1
        bsr     lstr
        move.w  (a1)+,d1
        addq.l  #2,a0
        subq.w  #1,d1
.c1     move.b  (a1)+,(a0)+
        dbra    d1,.c1
        moveq   #0,d0
        move.w  v_litc(a5),d0
        bsr     put_2dig
        bsr     str_close
        lea     v_str(a5),a1
        moveq   #112,d4
        moveq   #6,d5
        moveq   #0,d6
        bsr     print_centre
        lea     v_str+2(a5),a0  ; "BONUS: 012345"
        move.l  #'BONU',(a0)+
        move.w  #'S:',(a0)+
        move.b  #' ',(a0)+
        lea     v_bonus(a5),a1
        bsr     put_score
        bsr     str_close
        lea     v_str(a5),a1
        moveq   #126,d4
        moveq   #7,d5
        moveq   #0,d6
        bsr     print_centre
        move.w  #100,d7
        bsr     delay
        cmp.w   #99,v_round(a5)
        beq     .max
        addq.w  #1,v_round(a5)
.max    bra     newround

to_title:
        bsr     erase_all
        bra     menu

;---------------------------------------------------------------------
; Program exit
;---------------------------------------------------------------------
exit_prog:
        clr.l   v_mptr(a5)
        ifne    SOUND
        lea     snd_kill(pc),a3
        bsr     ipc
        endc
        lea     v_poll(a5),a0
        moveq   #MT_RPOLL,d0
        trap    #1
        move.l  v_hud(a5),a0
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  v_msg(a5),a0
        moveq   #IO_CLOSE,d0
        trap    #2
        moveq   #MT_DMODE,d0
        moveq   #4,d1
        moveq   #-1,d2
        trap    #1
        move.w  v_mode(a5),d7
        move.l  v_sp(a5),a4
        move.l  v_heap(a5),a0
        moveq   #MT_RECHP,d0
        trap    #1
        moveq   #0,d0
leave:                          ; d0 = error code, d7 = mode, a4 = SP
        tst.w   d7
        bne     .call
        move.l  d0,d3
        moveq   #MT_FRJOB,d0
        moveq   #-1,d1
        trap    #1
.call   move.l  a4,sp
        movem.l (sp)+,d1-d7/a0-a6
        rts

;=====================================================================
; Frame synchronisation
;=====================================================================
pcount: dc.w    0

pollrt: move.l  a0,-(sp)        ; called by QDOS 50 times a second
        lea     pcount(pc),a0
        addq.w  #1,(a0)
        move.l  (sp)+,a0
        rts

waitloop:
.w      move.w  pcount(pc),d0
        sub.w   v_last(a5),d0
        cmp.w   #LOOPF,d0
        blo     .w
        move.w  d0,v_lag(a5)
        move.w  pcount(pc),v_last(a5)
        rts

frame1: move.w  pcount(pc),d0   ; wait for the next frame (and play music)
.w      cmp.w   pcount(pc),d0
        beq     .w
        ; fallthrough

music_tick:                     ; one step of the music player
        ifne    SOUND
        movem.l d0-d3/a0-a3,-(sp)
        move.l  v_mptr(a5),d0
        beq.s   .e
        subq.w  #1,v_mwait(a5)
        bgt.s   .e
        move.l  d0,a0
.nt     moveq   #0,d1
        move.b  (a0)+,d1        ; pitch (0 = rest)
        moveq   #0,d2
        move.b  (a0)+,d2        ; frames
        cmp.b   #254,d1
        bne.s   .nl
        move.l  v_mloop(a5),a0  ; loop
        bra.s   .nt
.nl     cmp.b   #255,d1
        bne.s   .np
        clr.l   v_mptr(a5)      ; end of tune
        bra.s   .e
.np     move.l  a0,v_mptr(a5)
        move.w  d2,v_mwait(a5)
        tst.b   d1
        beq.s   .e
        lea     v_beep(a5),a3   ; IPC: initiate sound
        move.b  #$0a,(a3)
        move.b  #8,1(a3)
        clr.w   2(a3)
        move.w  #$aaaa,4(a3)
        move.b  d1,6(a3)        ; pitch 1 = pitch 2
        move.b  d1,7(a3)
        clr.w   8(a3)           ; no pitch steps
        mulu    #343,d2         ; 3/4 of the note in 43.64 us units
        move.b  d2,10(a3)       ; duration, low byte first
        lsr.w   #8,d2
        move.b  d2,11(a3)
        clr.w   12(a3)
        move.b  #1,14(a3)
        moveq   #MT_IPCOM,d0
        trap    #1
.e      movem.l (sp)+,d0-d3/a0-a3
        endc
        rts

music_play:                     ; a0 = tune (nothing if music is switched off)
        tst.w   v_music(a5)
        beq.s   .on
        clr.l   v_mptr(a5)
        rts
.on     move.l  a0,v_mptr(a5)
        move.l  a0,v_mloop(a5)
        move.w  #1,v_mwait(a5)
        rts

music_stop:
        clr.l   v_mptr(a5)
        ifne    SOUND
        movem.l d0-d3/a0-a3,-(sp)
        lea     snd_kill(pc),a3
        moveq   #MT_IPCOM,d0
        trap    #1
        movem.l (sp)+,d0-d3/a0-a3
        endc
        rts

delay:                          ; d7 = number of frames
        subq.w  #1,d7
.l      bsr     frame1
        dbra    d7,.l
        rts

;=====================================================================
; Input
;=====================================================================
readkeys:                       ; -> d0 = KEYROW(1)
        movem.l d1-d3/a0-a3,-(sp)
        lea     kr1(pc),a3
        moveq   #MT_IPCOM,d0
        trap    #1
        and.w   #$ff,d1
        move.w  d1,-(sp)
        lea     kr0(pc),a3      ; CTL2 / F1-F5: MiSTer maps the first pad here
        moveq   #MT_IPCOM,d0
        trap    #1
        move.w  (sp)+,d0
        btst    #1,d1           ; F1 = left
        beq.s   .f1
        bset    #K_LEFT,d0
.f1     btst    #4,d1           ; F3 = right
        beq.s   .f3
        bset    #K_RIGHT,d0
.f3     btst    #0,d1           ; F4 = up
        beq.s   .f4
        bset    #K_UP,d0
.f4     btst    #3,d1           ; F2 = down
        beq.s   .f2
        bset    #K_DOWN,d0
.f2     btst    #5,d1           ; F5 = fire
        beq.s   .f5
        bset    #K_SPACE,d0
.f5     move.w  v_keys(a5),v_pkeys(a5)
        move.w  d0,v_keys(a5)
        move.l  v_sysv(a5),a0   ; empty the keyboard queue, so that the keys
        move.l  $4c(a0),d1      ; pressed in the game do not end up in BASIC
        beq.s   .q
        move.l  d1,a0
        move.l  8(a0),12(a0)    ; next out = next in
.q
        movem.l (sp)+,d1-d3/a0-a3
        rts

ipc:    movem.l d0-d3/a0-a3,-(sp)
        moveq   #MT_IPCOM,d0
        trap    #1
        movem.l (sp)+,d0-d3/a0-a3
        rts

;=====================================================================
; Screen helpers
;=====================================================================
cls_all:                        ; clear screen and background buffer
        lea     SCREEN,a0
        move.l  v_bg(a5),a1
        move.w  #8192-1,d0
        moveq   #0,d1
.l      move.l  d1,(a0)+
        move.l  d1,(a1)+
        dbra    d0,.l
        rts

restore_pf:                     ; restore whole playfield from buffer
        move.l  v_bg(a5),a0
        lea     PF_TOP*LINEB(a0),a0
        lea     SCREEN+PF_TOP*LINEB,a1
        move.w  #(256-PF_TOP)*LINEB/16-1,d0
.l      move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        dbra    d0,.l
        rts

; setpix: d0 = x, d1 = y, d2 = colour, a4 = buffer
setpix: movem.l d3-d6/a1,-(sp)
        move.w  d1,d3
        lsl.w   #7,d3
        move.w  d0,d4
        lsr.w   #2,d4
        add.w   d4,d4
        add.w   d4,d3
        move.w  d0,d4
        and.w   #3,d4
        add.w   d4,d4
        lea     clrmask(pc),a1
        move.w  0(a4,d3.w),d5
        and.w   0(a1,d4.w),d5
        move.w  d2,d6
        lsl.w   #3,d6
        add.w   d4,d6
        or.w    8(a1,d6.w),d5
        move.w  d5,0(a4,d3.w)
        movem.l (sp)+,d3-d6/a1
        rts

; fillrect: d0 = x, d1 = y, d6 = width, d7 = height, d2 = colour
fillrect:
        movem.l d0-d1/d6-d7,-(sp)
        subq.w  #1,d7
        bmi     .e
.y      movem.w d0/d6,-(sp)
        subq.w  #1,d6
.x      bsr     setpix
        addq.w  #1,d0
        dbra    d6,.x
        movem.w (sp)+,d0/d6
        addq.w  #1,d1
        dbra    d7,.y
.e      movem.l (sp)+,d0-d1/d6-d7
        rts

; drawbrick: d0 = x, d1 = y, d6 = width, d7 = height (brickwork)
drawbrick:
        movem.l d0-d7,-(sp)
        moveq   #0,d5           ; row within brick
        subq.w  #1,d7
.y      movem.w d0/d6,-(sp)
        subq.w  #1,d6
.x      move.w  v_bc1(a5),d2    ; main
        tst.w   d5
        bne     .n0
        move.w  v_bc0(a5),d2    ; top edge
        bra     .p
.n0     cmp.w   #3,d5
        bne     .n3
        move.w  v_bc2(a5),d2    ; mortar
        bra     .p
.n3     move.w  d0,d4
        cmp.w   #3,d5
        blt     .u
        addq.w  #4,d4
.u      and.w   #7,d4
        bne     .p
        move.w  v_bc3(a5),d2    ; vertical joint
.p      bsr     setpix
        addq.w  #1,d0
        dbra    d6,.x
        movem.w (sp)+,d0/d6
        addq.w  #1,d1
        addq.w  #1,d5
        cmp.w   #6,d5
        bne     .k
        moveq   #0,d5
.k      dbra    d7,.y
        movem.l (sp)+,d0-d7
        rts

rand:                           ; -> d0.w random number
        move.l  v_rand(a5),d0
        mulu    #25173,d0
        add.l   #13849,d0
        move.l  d0,v_rand(a5)
        swap    d0
        rts

;=====================================================================
; Level setup
;=====================================================================
setup_level:
        move.l  v_bg(a5),a0     ; clear background buffer only
        move.w  #8192-1,d0
        moveq   #0,d1
.cl     move.l  d1,(a0)+
        dbra    d0,.cl
        move.w  v_round(a5),d0
        subq.w  #1,d0
        ext.l   d0
        divu    #NLEV,d0
        swap    d0              ; remainder = level number
        move.w  d0,v_lvl(a5)
        add.w   d0,d0
        LEAX    lvltab,a0
        move.w  0(a0,d0.w),d1
        lea     0(a0,d1.w),a3   ; a3 = level descriptor
        move.w  6(a3),d1
        lea     0(a3,d1.w),a1
        move.l  a1,v_plat(a5)
        move.w  10(a3),d1
        lea     0(a3,d1.w),a1
        move.l  a1,v_spwt(a5)
        ; difficulty: gentle start, harder every round
        tst.w   v_diff(a5)
        bne     .easy
        move.w  v_round(a5),d0
        move.w  d0,d1
        mulu    #3,d1
        addq.w  #8,d1           ; enemy speed 11, 14, 17 ... 40
        cmp.w   #40,d1
        ble.s   .s1
        moveq   #40,d1
.s1     move.w  d1,v_espd(a5)
        move.w  d0,d1
        subq.w  #1,d1
        lsr.w   #1,d1
        addq.w  #2,d1           ; max enemies 2, 2, 3, 3, 4 ... 6
        cmp.w   #MAXEN,d1
        ble.s   .s2
        moveq   #MAXEN,d1
.s2     move.w  d1,v_maxen(a5)
        move.w  d0,d1
        lsl.w   #3,d1
        neg.w   d1
        add.w   #120,d1         ; spawn interval 112, 104 ... 30 loops
        cmp.w   #30,d1
        bge.s   .s3
        moveq   #30,d1
.s3     move.w  d1,v_spwin(a5)
        bra.s   .dd
.easy   move.w  v_round(a5),d0  ; easy: slower, fewer enemies
        move.w  d0,d1
        add.w   d1,d1
        addq.w  #6,d1           ; speed 8, 10, 12 ... 30
        cmp.w   #30,d1
        ble.s   .e1
        moveq   #30,d1
.e1     move.w  d1,v_espd(a5)
        move.w  d0,d1
        subq.w  #1,d1
        lsr.w   #1,d1
        addq.w  #1,d1           ; max enemies 1, 1, 2, 2 ... 4
        cmp.w   #4,d1
        ble.s   .e2
        moveq   #4,d1
.e2     move.w  d1,v_maxen(a5)
        move.w  d0,d1
        lsl.w   #3,d1
        neg.w   d1
        add.w   #150,d1         ; spawn interval 142 ... 45
        cmp.w   #45,d1
        bge.s   .e3
        moveq   #45,d1
.e3     move.w  d1,v_spwin(a5)
.dd     clr.w   v_litc(a5)

        move.l  v_bg(a5),a4
        ; stars
        moveq   #59,d7
.st     bsr     rand
        move.w  d0,d3
        and.w   #255,d0
        cmp.w   #XMIN,d0
        blt     .sn
        cmp.w   #251,d0
        bgt     .sn
        move.w  d3,d1
        lsr.w   #8,d1
        and.w   #127,d1
        add.w   #24,d1
        moveq   #7,d2
        btst    #4,d3
        beq     .sw
        moveq   #5,d2
.sw     bsr     setpix
.sn     dbra    d7,.st
        ; moon (x = 0: none)
        move.w  16(a3),v_moony(a5)
        move.w  14(a3),v_moonx(a5)
        beq     .nm
        bsr     draw_moon
.nm     move.w  18(a3),v_bc0(a5)
        move.w  20(a3),v_bc1(a5)
        move.w  22(a3),v_bc2(a5)
        move.w  24(a3),v_bc3(a5)
        ; backdrop (byte code from backdrops.py)
        move.w  12(a3),d1
        lea     0(a3,d1.w),a2
        bsr     draw_spans
        ; ceiling and walls
        moveq   #0,d0
        moveq   #PF_TOP,d1
        move.w  #256,d6
        moveq   #PF_CEIL-PF_TOP,d7
        bsr     drawbrick
        moveq   #0,d0
        moveq   #PF_CEIL,d1
        moveq   #XMIN,d6
        move.w  #256-PF_CEIL,d7
        bsr     drawbrick
        move.w  #252,d0
        bsr     drawbrick
        ; platforms (first = floor)
        move.l  v_plat(a5),a2
.pl     move.w  (a2)+,d0
        bmi     .pd
        move.w  (a2)+,d1
        move.w  (a2)+,d6
        move.w  (a2)+,d7
        bsr     drawbrick
        bra     .pl
.pd
        ; bombs
        move.w  8(a3),d1
        lea     0(a3,d1.w),a2
        lea     v_bombs(a5),a0
        moveq   #0,d6
.bl     move.w  (a2)+,d0
        bmi     .bdn
        move.w  d0,b_x(a0)
        move.w  (a2)+,b_y(a0)
        move.w  #1,b_state(a0)
        clr.w   b_dirty(a0)
        bsr     bomb_offset     ; d0 = Offset
        move.l  v_bg(a5),a1
        add.w   d0,a1
        lea     b_save(a0),a6
        moveq   #7,d1
.sv     move.l  (a1),(a6)+
        lea     LINEB(a1),a1
        dbra    d1,.sv
        movem.l d6/a2,-(sp)
        move.w  #-1,v_lit(a5)
        bsr     bomb_paint
        movem.l (sp)+,d6/a2
        lea     b_size(a0),a0
        addq.w  #1,d6
        bra     .bl
.bdn
        ifd     FEWBOMBS        ; test build: only the first bombs
        moveq   #FEWBOMBS,d6
        endc
        move.w  d6,v_nb(a5)
        move.w  d6,v_bleft(a5)
        move.w  #-1,v_lit(a5)
        clr.w   v_flash(a5)
        ; remember start position
        move.w  2(a3),d0
        lsl.w   #4,d0
        move.w  d0,v_jsx(a5)
        move.w  4(a3),d0
        lsl.w   #4,d0
        move.w  d0,v_jsy(a5)
        bra     restore_pf

draw_moon:                      ; crescent moon top right (ellipse due to wide Mode 8 pixels)
        moveq   #-9,d4          ; dx
.x      moveq   #-12,d5         ; dy
.y      move.w  d5,d1
        muls    d1,d1
        mulu    #9,d1           ; (3dy)^2
        move.w  d4,d0
        muls    d0,d0
        lsl.w   #4,d0           ; (4dx)^2
        add.w   d1,d0
        cmp.w   #36*36,d0
        bgt     .n
        move.w  d4,d0           ; second circle, shifted right
        subq.w  #4,d0
        muls    d0,d0
        lsl.w   #4,d0
        add.w   d1,d0
        moveq   #6,d2
        cmp.w   #34*34,d0
        bgt     .c
        moveq   #0,d2
.c      move.w  v_moonx(a5),d0
        add.w   d4,d0
        move.w  v_moony(a5),d1
        add.w   d5,d1
        bsr     setpix
.n      addq.w  #1,d5
        cmp.w   #13,d5
        bne     .y
        addq.w  #1,d4
        cmp.w   #10,d4
        bne     .x
        rts

draw_spans:                     ; a2 = backdrop byte code, a4 = buffer
; y<248: hspan y,x0,len,col  248: PROFILE  249: EDGE  250: RECT
; 251: COLS  255: end   (see backdrops.py)
.op     moveq   #0,d1
        move.b  (a2)+,d1
        cmp.w   #248,d1
        bhs     .spec
        moveq   #0,d0
        move.b  (a2)+,d0        ; x0
        moveq   #0,d6
        move.b  (a2)+,d6        ; length
        bsr     .col
        bsr     hrun
        bra     .op
.col    moveq   #0,d5           ; d5 = colour|pattern, d2 = colour
        move.b  (a2)+,d5
        move.w  d5,d2
        and.w   #7,d2
        rts
.spec   sub.w   #248,d1
        beq     .prof
        subq.w  #1,d1
        beq     .edge
        subq.w  #1,d1
        beq     .rect
        subq.w  #1,d1
        beq     .cols
        rts
.rect   moveq   #0,d0
        move.b  (a2)+,d0
        moveq   #0,d1
        move.b  (a2)+,d1
        moveq   #0,d6
        move.b  (a2)+,d6
        moveq   #0,d7
        move.b  (a2)+,d7
        bsr     .col
        subq.w  #1,d7
.rl     bsr     hrun
        addq.w  #1,d1
        dbra    d7,.rl
        bra     .op
.prof   moveq   #0,d0
        move.b  (a2)+,d0        ; x0
        moveq   #0,d7
        move.b  (a2)+,d7        ; columns
        bsr     .col
        moveq   #0,d4
        move.b  (a2)+,d4        ; bottom y
        subq.w  #1,d7
.pl     moveq   #0,d1
        move.b  (a2)+,d1        ; top y
        move.w  d4,d6
        sub.w   d1,d6
        addq.w  #1,d6
        bsr     vrun
        addq.w  #1,d0
        dbra    d7,.pl
        bra     .op
.edge   moveq   #0,d0
        move.b  (a2)+,d0
        moveq   #0,d7
        move.b  (a2)+,d7
        bsr     .col
        subq.w  #1,d7
.el     moveq   #0,d1
        move.b  (a2)+,d1
        bsr     plot
        addq.w  #1,d0
        dbra    d7,.el
        bra     .op
.cols   moveq   #0,d0
        move.b  (a2)+,d0
        moveq   #0,d7
        move.b  (a2)+,d7
        bsr     .col
        subq.w  #1,d7
.cl     moveq   #0,d1
        move.b  (a2)+,d1        ; top y
        moveq   #0,d6
        move.b  (a2)+,d6        ; length
        bsr     vrun
        addq.w  #1,d0
        dbra    d7,.cl
        bra     .op

; hrun/vrun: d0 = x, d1 = y, d6 = count, d2 = colour, d5 = colour|pattern<<3
; draw directly into the buffer (a4); solid spans are filled a word at a time
hrun:   movem.l d0/d3-d7/a1/a3,-(sp)
        tst.w   d6
        ble.s   .e
        bsr     pixaddr
        move.w  d2,d7
        lsl.w   #3,d7           ; pixtab row of this colour
        move.w  d5,d3
        and.w   #$38,d3
        bne.s   .pl
.sol    tst.w   d4
        bne.s   .s1
        cmp.w   #4,d6
        blo.s   .s1
        move.w  d2,d3
        add.w   d3,d3
        move.w  72(a3,d3.w),d3  ; fullw: all four pixels in this colour
.fw     move.w  d3,(a1)+
        subq.w  #4,d6
        cmp.w   #4,d6
        bhs.s   .fw
        tst.w   d6
        beq.s   .e
.s1     bsr.s   .px
        subq.w  #1,d6
        bne.s   .sol
        bra.s   .e
.pl     bsr     hrunp           ; patterned span: word masks
.e      movem.l (sp)+,d0/d3-d7/a1/a3
        rts
.px     move.w  (a1),d3         ; set one pixel and advance
        and.w   0(a3,d4.w),d3
        add.w   d7,d4
        or.w    8(a3,d4.w),d3
        sub.w   d7,d4
        move.w  d3,(a1)
.nx     addq.w  #2,d4
        cmp.w   #8,d4
        blo.s   .n2
        moveq   #0,d4
        addq.l  #2,a1
.n2     rts

vrun:   movem.l d1/d3-d7/a1/a3,-(sp)
        tst.w   d6
        ble.s   .e
        bsr      pixaddr
        move.w  d2,d7
        lsl.w   #3,d7
        add.w   d4,d7           ; pixtab offset of colour at this pixel
.l      bsr      pattest
        beq.s   .n
        move.w  (a1),d3
        and.w   0(a3,d4.w),d3
        or.w    8(a3,d7.w),d3
        move.w  d3,(a1)
.n      lea     LINEB(a1),a1
        addq.w  #1,d1
        subq.w  #1,d6
        bne.s   .l
.e      movem.l (sp)+,d1/d3-d7/a1/a3
        rts

; hrunp: patterned span (d0..d6 as hrun, a1/d4/a3 from pixaddr)
; uses pattab: pattern masks for 8 pixels, so whole words are done at once
hrunp:  movem.l d0-d7/a0,-(sp)
        move.w  d5,d3
        lsr.w   #3,d3
        and.w   #7,d3
        lsl.w   #5,d3           ; mode * 32
        move.w  d1,d7
        and.w   #7,d7
        lsl.w   #2,d7
        add.w   d7,d3
        lea     pattab(pc),a0
        add.w   d3,a0           ; (a0) = mask pixels 0-3, 2(a0) = 4-7
        move.w  d2,d7
        add.w   d7,d7
        move.w  72(a3,d7.w),d7  ; colour in all four pixels
        move.w  d0,d2
        lsr.w   #1,d2
        and.w   #2,d2           ; which half of the 8 pixel pattern
        ; first word
        move.w  d4,d3
        lsr.w   #1,d3           ; p
        add.w   d6,d3           ; e = p + count
        move.w  88(a3,d4.w),d5  ; lmask[p]
        cmp.w   #4,d3
        bhs.s   .f1
        add.w   d3,d3
        and.w   96(a3,d3.w),d5  ; & rmask[e]
        moveq   #0,d6
        bra.s   .f2
.f1     subq.w  #4,d3
        move.w  d3,d6           ; pixels left after this word
.f2     bsr.s   .wr
        ; full words
.mid    cmp.w   #4,d6
        blo.s   .last
        moveq   #-1,d5
        bsr.s   .wr
        subq.w  #4,d6
        bra.s   .mid
.last   tst.w   d6
        beq.s   .e
        move.w  d6,d3
        add.w   d3,d3
        move.w  96(a3,d3.w),d5  ; rmask[count]
        bsr.s   .wr
.e      movem.l (sp)+,d0-d7/a0
        rts
.wr     and.w   0(a0,d2.w),d5   ; d5 = span mask & pattern mask
        move.w  d5,d0
        not.w   d0
        and.w   (a1),d0
        move.w  d7,d1
        and.w   d5,d1
        or.w    d1,d0
        move.w  d0,(a1)+
        eor.w   #2,d2
        rts

pixaddr:                        ; d0 = x, d1 = y -> a1 = word, d4 = pixel*2, a3 = clrmask
        move.w  d1,d3
        lsl.w   #7,d3
        move.w  d0,d4
        lsr.w   #2,d4
        add.w   d4,d4
        add.w   d4,d3
        lea     0(a4,d3.w),a1
        move.w  d0,d4
        and.w   #3,d4
        add.w   d4,d4
        lea     clrmask(pc),a3
        rts

plot:   bsr.s   pattest         ; single pixel through the pattern
        beq.s   .n
        bsr     setpix
.n      rts

; pattest: d0 = x, d1 = y, d5 = colour|pattern<<3 -> NE = draw pixel (uses d3)
; same rules as pat() in backdrops.py
pattest:
        move.w  d5,d3
        lsr.w   #2,d3
        and.w   #14,d3
        move.w  .tab(pc,d3.w),d3
        jmp     .tab(pc,d3.w)
.tab    dc.w    .yes-.tab,.m1-.tab,.m2-.tab,.m3-.tab
        dc.w    .m4-.tab,.m5-.tab,.m6-.tab,.m7-.tab
.m1     move.w  d0,d3           ; checker
        add.w   d1,d3
        btst    #0,d3
        bne.s   .no
        bra.s   .yes
.m2     btst    #0,d0           ; dots 25%
        bne.s   .no
.m3     btst    #0,d1           ; h-lines
        bne.s   .no
        bra.s   .yes
.m4     move.w  d0,d3           ; window grid
        and.w   #3,d3
        beq.s   .no
        cmp.w   #3,d3
        beq.s   .no
        move.w  d1,d3
        and.w   #7,d3
        cmp.w   #2,d3
        blo.s   .no
        cmp.w   #4,d3
        bhi.s   .no
        bra.s   .yes
.m5     move.w  d1,d3           ; brick lines
        and.w   #3,d3
        beq.s   .yes
        move.w  d1,d3
        lsr.w   #2,d3
        and.w   #1,d3
        lsl.w   #2,d3
        add.w   d0,d3
        and.w   #7,d3
        beq.s   .yes
        bra.s   .no
.m6     btst    #0,d0           ; v-lines
        bne.s   .no
        bra.s   .yes
.m7     move.w  d0,d3           ; dots 12.5%
        and.w   #3,d3
        bne.s   .no
        btst    #0,d1
        bne.s   .no
.yes    moveq   #1,d3
        rts
.no     moveq   #0,d3
        rts

;=====================================================================
; Bombs
;=====================================================================
bomb_offset:                    ; a0 = bomb -> d0.w = offset
        move.w  b_y(a0),d0
        lsl.w   #7,d0
        move.w  d1,-(sp)
        move.w  b_x(a0),d1
        lsr.w   #1,d1
        add.w   d1,d0
        move.w  (sp)+,d1
        rts

; bomb_paint: a0 = bomb, d6 = index. Writes to buffer and screen.
bomb_paint:
        movem.l d0-d3/a1-a3,-(sp)
        bsr     bomb_offset
        moveq   #0,d1
        move.w  d0,d1
        move.l  v_bg(a5),a1
        add.l   d1,a1
        lea     SCREEN,a2
        add.l   d1,a2
        ; restore background
        lea     b_save(a0),a3
        moveq   #7,d2
.r      move.l  (a3),(a1)
        move.l  (a3)+,(a2)
        lea     LINEB(a1),a1
        lea     LINEB(a2),a2
        dbra    d2,.r
        tst.w   b_state(a0)
        beq     .e
        lea     -8*LINEB(a1),a1
        lea     -8*LINEB(a2),a2
        LEAX    bomb_n,a3
        cmp.w   v_lit(a5),d6
        bne     .d
        LEAX    bomb_l1,a3
        btst    #2,v_flash+1(a5)
        beq     .d
        LEAX    bomb_l2,a3
.d      moveq   #7,d2
.dl     move.w  (a3)+,d0        ; mask
        move.w  (a3)+,d1        ; data
        move.w  (a1),d3
        and.w   d0,d3
        or.w    d1,d3
        move.w  d3,(a1)
        move.w  (a2),d3
        and.w   d0,d3
        or.w    d1,d3
        move.w  d3,(a2)
        move.w  (a3)+,d0
        move.w  (a3)+,d1
        move.w  2(a1),d3
        and.w   d0,d3
        or.w    d1,d3
        move.w  d3,2(a1)
        move.w  2(a2),d3
        and.w   d0,d3
        or.w    d1,d3
        move.w  d3,2(a2)
        lea     LINEB(a1),a1
        lea     LINEB(a2),a2
        dbra    d2,.dl
.e      movem.l (sp)+,d0-d3/a1-a3
        rts

bomb_refresh:                   ; call after erase_all
        addq.w  #1,v_flash(a5)
        move.w  v_lit(a5),d0
        bmi     .nl
        move.w  v_flash(a5),d1
        and.w   #3,d1
        bne     .nl
        mulu    #b_size,d0
        lea     v_bombs(a5),a0
        move.w  #1,b_dirty(a0,d0.w)
.nl     lea     v_bombs(a5),a0
        move.w  v_nb(a5),d7
        subq.w  #1,d7
        bmi     .e
        moveq   #0,d6
.l      tst.w   b_dirty(a0)
        beq     .n
        clr.w   b_dirty(a0)
        bsr     bomb_paint
.n      lea     b_size(a0),a0
        addq.w  #1,d6
        dbra    d7,.l
.e      rts

check_bombs:                    ; collision Jack <-> bombs
        lea     v_spr(a5),a1
        move.w  s_x(a1),d2
        asr.w   #4,d2
        addq.w  #1,d2           ; left
        move.w  d2,d3
        add.w   #9,d3           ; right
        move.w  s_y(a1),d4
        asr.w   #4,d4           ; top
        move.w  d4,d5
        add.w   #SPRH-1,d5      ; bottom
        lea     v_bombs(a5),a0
        move.w  v_nb(a5),d7
        subq.w  #1,d7
        bmi     .e
        moveq   #0,d6
.l      tst.w   b_state(a0)
        beq     .n
        move.w  b_x(a0),d0
        cmp.w   d0,d3
        blt     .n
        addq.w  #7,d0
        cmp.w   d0,d2
        bgt     .n
        move.w  b_y(a0),d0
        cmp.w   d0,d5
        blt     .n
        addq.w  #7,d0
        cmp.w   d0,d4
        bgt     .n
        bsr     collect
.n      lea     b_size(a0),a0
        addq.w  #1,d6
        dbra    d7,.l
.e      rts

collect:                        ; a0 = bomb, d6 = index
        movem.l d0-d7/a0-a1,-(sp)
        clr.w   b_state(a0)
        move.w  #1,b_dirty(a0)
        subq.w  #1,v_bleft(a5)
        move.w  #1,v_hudd(a5)
        addq.w  #1,v_bcnt(a5)   ; bonus item: bomb 1 point, lit bomb 2 points
        cmp.w   v_lit(a5),d6
        bne.s   .nlt
        addq.w  #1,v_bcnt(a5)
        addq.w  #1,v_litc(a5)
.nlt    cmp.w   #BONUSEVERY,v_bcnt(a5)
        blo     .nb
        lea     BONUSSPR(a5),a1
        tst.w   s_act(a1)
        bne     .nb
        clr.w   v_bcnt(a5)
        bsr     spawn_bonus
.nb
        move.l  #$100,d0
        move.w  v_lit(a5),d1
        cmp.w   d1,d6
        bne     .nl
        move.l  #$200,d0        ; lit bomb scores double
        ifne    SOUND
        lea     snd_lit(pc),a3
        bsr     ipc
        endc
        bra     .nx
.nl     ifne    SOUND
        lea     snd_bomb(pc),a3
        bsr     ipc
        endc
        tst.w   d1
        bpl     .add            ; another one stays lit
.nx     ; next lit bomb = next remaining one in list order
        move.w  #-1,v_lit(a5)
        move.w  v_nb(a5),d2
        move.w  d6,d3
        move.w  d2,d4
        subq.w  #2,d4
        bmi     .add
.f      addq.w  #1,d3
        cmp.w   d2,d3
        blt     .f1
        moveq   #0,d3
.f1     move.w  d3,d5
        mulu    #b_size,d5
        lea     v_bombs(a5),a1
        tst.w   b_state(a1,d5.w)
        beq     .f2
        move.w  d3,v_lit(a5)
        move.w  #1,b_dirty(a1,d5.w)
        bra     .add
.f2     dbra    d4,.f
.add    bsr     add_score
        movem.l (sp)+,d0-d7/a0-a1
        rts

add_score:                      ; d0.l = points (BCD)
        move.l  d0,v_ptsb(a5)
        lea     v_ptsb+4(a5),a0
        lea     v_score+4(a5),a1
        move    #4,ccr
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        rts

;=====================================================================
; Sprites
;=====================================================================
init_actors:
        lea     v_spr(a5),a0
        move.w  #s_size*NSPR/2-1,d0
.c      clr.w   (a0)+
        dbra    d0,.c
        lea     v_spr(a5),a0
        move.w  #1,s_act(a0)
        move.w  v_jsx(a5),s_x(a0)
        move.w  v_jsy(a5),s_y(a0)
        move.w  #1,s_gnd(a0)
        LEAX    spr_jack,a1
        move.l  a1,s_img(a0)
        move.w  #75,v_spawn(a5) ; first enemy after 3 s
        move.w  #INVT,v_inv(a5)
        ifd     NOENEMY         ; test build: no enemies, no protection
        move.w  #30000,v_spawn(a5)
        clr.w   v_inv(a5)
        endc
        clr.w   v_dead(a5)
        clr.w   v_freeze(a5)
        clr.w   v_bcnt(a5)
        clr.w   v_btest(a5)
        rts

; render: instead of "erase all, then draw all" every sprite is erased
; and drawn again on its own, from the top of the screen downwards, so a
; sprite is missing from the screen only for a moment (less flicker).
; Sprites already done this frame that touch an erased area are redrawn.
render: movem.l d0-d7/a0-a4,-(sp)
        lea     v_ord(a5),a3
        lea     v_okey(a5),a1
        moveq   #0,d7           ; number of entries
        lea     v_spr(a5),a0
        moveq   #NSPR-1,d6
.col    bsr     visible
        bne.s   .k1
        tst.w   s_drawn(a0)
        beq.s   .nx
        move.w  s_soff(a0),d4   ; only to be erased: old line
        lsr.w   #7,d4
        bra.s   .ins
.k1     move.w  s_y(a0),d4
        asr.w   #4,d4
.ins    move.w  d7,d3           ; insertion sort by screen line
.sh     tst.w   d3
        beq.s   .put
        move.w  d3,d2
        subq.w  #1,d2
        add.w   d2,d2
        cmp.w   0(a1,d2.w),d4
        bge.s   .put
        move.w  0(a1,d2.w),2(a1,d2.w)
        add.w   d2,d2
        move.l  0(a3,d2.w),4(a3,d2.w)
        subq.w  #1,d3
        bra.s   .sh
.put    move.w  d3,d2
        add.w   d2,d2
        move.w  d4,0(a1,d2.w)
        add.w   d2,d2
        move.l  a0,0(a3,d2.w)
        addq.w  #1,d7
.nx     lea     s_size(a0),a0
        dbra    d6,.col
        moveq   #0,d6
.pr     cmp.w   d7,d6
        bge.s   .done
        move.w  d6,d2
        lsl.w   #2,d2
        move.l  0(a3,d2.w),a0
        tst.w   s_drawn(a0)
        beq.s   .dr
        move.w  s_soff(a0),d4
        bsr     erase_spr
        moveq   #0,d5           ; repair sprites drawn before that overlap
.rp     cmp.w   d6,d5
        bge.s   .dr
        move.w  d5,d2
        lsl.w   #2,d2
        move.l  0(a3,d2.w),a4
        tst.w   s_drawn(a4)
        beq.s   .rn
        move.w  s_soff(a4),d0
        bsr     overlap
        beq.s   .rn
        exg     a0,a4
        bsr     draw_spr
        exg     a0,a4
.rn     addq.w  #1,d5
        bra.s   .rp
.dr     bsr     visible
        beq.s   .ad
        bsr     draw_spr
.ad     addq.w  #1,d6
        bra.s   .pr
.done   movem.l (sp)+,d0-d7/a0-a4
        rts

visible:                        ; a0 = sprite -> d0 = 1 (NE) if it is to be shown
        tst.w   s_act(a0)
        beq.s   .no
        move.l  a0,d0
        sub.l   a5,d0
        cmp.l   #BONUSSPR,d0
        bne.s   .nb
        tst.w   s_gnd(a0)       ; bonus blinking off
        bne.s   .no
        bra.s   .yes
.nb     cmp.l   #v_spr,d0
        bne.s   .yes
        tst.w   v_inv(a5)       ; Jack blinking while protected
        beq.s   .yes
        btst    #2,v_inv+1(a5)
        bne.s   .no
.yes    moveq   #1,d0
        rts
.no     moveq   #0,d0
        rts

overlap:                        ; d0, d4 = screen offsets -> d1 = 1 (NE) if the 16x16 areas touch
        movem.l d2-d3,-(sp)
        move.w  d0,d2
        lsr.w   #7,d2
        move.w  d4,d3
        lsr.w   #7,d3
        sub.w   d3,d2
        bpl.s   .a
        neg.w   d2
.a      cmp.w   #SPRH,d2
        bhs.s   .no
        move.w  d0,d2
        and.w   #127,d2
        move.w  d4,d3
        and.w   #127,d3
        sub.w   d3,d2
        bpl.s   .b
        neg.w   d2
.b      cmp.w   #8,d2
        bhs.s   .no
        moveq   #1,d1
        movem.l (sp)+,d2-d3
        rts
.no     moveq   #0,d1
        movem.l (sp)+,d2-d3
        rts

erase_all:                      ; reverse drawing order
        lea     v_spr(a5),a0
        bsr     erase_spr
        lea     BONUSSPR(a5),a0
        bsr     erase_spr
        lea     LASTSPR(a5),a0
        moveq   #MAXEN-1,d7
.l      bsr     erase_spr
        lea     -s_size(a0),a0
        dbra    d7,.l
        rts

erase_spr:
        tst.w   s_drawn(a0)
        beq     .e
        clr.w   s_drawn(a0)
        moveq   #0,d0
        move.w  s_soff(a0),d0
        lea     SCREEN,a1
        add.l   d0,a1
        move.l  v_bg(a5),a2
        add.l   d0,a2
        moveq   #SPRH-1,d1
.l      move.l  (a2)+,(a1)+
        move.l  (a2)+,(a1)+
        lea     LINEB-8(a1),a1
        lea     LINEB-8(a2),a2
        dbra    d1,.l
.e      rts

draw_all:                       ; enemies first, Jack on top
        lea     v_spr+s_size(a5),a0
        moveq   #MAXEN-1,d7
.l      tst.w   s_act(a0)
        beq     .n
        bsr     draw_spr
.n      lea     s_size(a0),a0
        dbra    d7,.l
        lea     BONUSSPR(a5),a0 ; bonus item (s_gnd = 1: blinked off)
        tst.w   s_act(a0)
        beq     .j
        tst.w   s_gnd(a0)
        bne     .j
        bsr     draw_spr
.j      lea     v_spr(a5),a0
        tst.w   v_inv(a5)       ; Jack blinks while protected
        beq.s   draw_spr
        btst    #2,v_inv+1(a5)
        beq.s   draw_spr
        rts

draw_spr:
        move.w  s_y(a0),d0
        asr.w   #4,d0
        lsl.w   #7,d0
        move.w  s_x(a0),d1
        asr.w   #4,d1
        move.w  d1,d2
        and.w   #3,d2
        lsr.w   #2,d1
        add.w   d1,d1
        add.w   d1,d0
        move.w  d0,s_soff(a0)
        move.w  #1,s_drawn(a0)
        move.l  s_img(a0),a2
        lsl.w   #8,d2
        add.w   d2,a2
        lea     SCREEN,a1
        and.l   #$ffff,d0
        add.l   d0,a1
        moveq   #SPRH-1,d3
.l
        rept    4
        move.w  (a1),d1
        and.w   (a2)+,d1
        or.w    (a2)+,d1
        move.w  d1,(a1)+
        endr
        lea     LINEB-8(a1),a1
        dbra    d3,.l
        rts

;=====================================================================
; Movement with platform collision
; a0 = sprite. s_flag bit 0 = blocked sideways
;=====================================================================
body_move:
        movem.l d0-d7/a1-a2,-(sp)
        clr.w   s_flag(a0)
        move.l  v_plat(a5),a2
        ; --- horizontal ---
        move.w  s_x(a0),d0
        add.w   s_vx(a0),d0
        move.w  d0,d1
        asr.w   #4,d1
        cmp.w   #XMIN,d1
        bge     .x1
        moveq   #XMIN,d1
        bra     .xw
.x1     cmp.w   #XMAX,d1
        ble     .x2
        move.w  #XMAX,d1
.xw     move.w  d1,d0
        lsl.w   #4,d0
        bset    #0,s_flag+1(a0)
.x2     move.w  s_y(a0),d2
        asr.w   #4,d2           ; top
        move.w  d2,d3
        add.w   #SPRH-1,d3      ; bottom
        move.w  d1,d4
        addq.w  #1,d4           ; left
        move.w  d1,d5
        add.w   #10,d5          ; right
        move.l  a2,a1
.hl     move.w  (a1)+,d6
        bmi     .hd
        cmp.w   d6,d5
        blt     .hn
        move.w  d6,d7
        add.w   2(a1),d7
        cmp.w   d7,d4
        bge     .hn
        move.w  (a1),d7
        cmp.w   d7,d3
        blt     .hn
        add.w   4(a1),d7
        cmp.w   d7,d2
        bge     .hn
        move.w  s_x(a0),d0      ; blocked
        bset    #0,s_flag+1(a0)
        bra     .hd
.hn     addq.l  #6,a1
        bra     .hl
.hd     move.w  d0,s_x(a0)
        ; --- vertical ---
        move.w  d0,d1
        asr.w   #4,d1
        move.w  d1,d4
        addq.w  #1,d4
        move.w  d1,d5
        add.w   #10,d5
        move.w  s_y(a0),d6
        asr.w   #4,d6           ; old top
        move.w  s_y(a0),d0
        add.w   s_vy(a0),d0     ; new y (1/16)
        move.w  d0,d3
        asr.w   #4,d3           ; new top
        tst.w   s_vy(a0)
        bmi     .up
        ; falling / standing: highest platform top crossed
        add.w   #SPRH,d6        ; old bottom
        move.w  d3,d7
        add.w   #SPRH,d7        ; new bottom
        move.w  #$7fff,d1
        move.l  a2,a1
.fl     move.w  (a1)+,d2
        bmi     .fd
        cmp.w   d2,d5
        blt     .fn
        add.w   2(a1),d2
        cmp.w   d2,d4
        bge     .fn
        move.w  (a1),d2
        cmp.w   d6,d2
        blt     .fn
        cmp.w   d7,d2
        bgt     .fn
        cmp.w   d1,d2
        bge     .fn
        move.w  d2,d1
.fn     addq.l  #6,a1
        bra     .fl
.fd     cmp.w   #$7fff,d1
        beq     .air
        sub.w   #SPRH,d1
        lsl.w   #4,d1
        move.w  d1,d0
        clr.w   s_vy(a0)
        move.w  #1,s_gnd(a0)
        bra     .vd
.air    clr.w   s_gnd(a0)
        bra     .vd
.up     ; rising: bump head on platform underside
        moveq   #-1,d1
        move.l  a2,a1
.ul     move.w  (a1)+,d7
        bmi     .ud
        cmp.w   d7,d5
        blt     .un
        add.w   2(a1),d7
        cmp.w   d7,d4
        bge     .un
        move.w  (a1),d7
        add.w   4(a1),d7        ; underside
        cmp.w   d6,d7
        bgt     .un
        cmp.w   d3,d7
        ble     .un
        cmp.w   d1,d7
        ble     .un
        move.w  d7,d1
.un     addq.l  #6,a1
        bra     .ul
.ud     tst.w   d1
        bmi     .ce
        lsl.w   #4,d1
        move.w  d1,d0
        clr.w   s_vy(a0)
.ce     cmp.w   #PF_CEIL<<4,d0
        bge     .cn
        move.w  #PF_CEIL<<4,d0
        clr.w   s_vy(a0)
.cn     clr.w   s_gnd(a0)
.vd     move.w  d0,s_y(a0)
        movem.l (sp)+,d0-d7/a1-a2
        rts

;=====================================================================
; Jack
;=====================================================================
update_jack:
        lea     v_spr(a5),a0
        move.w  v_keys(a5),d3
        moveq   #0,d1
        btst    #K_LEFT,d3
        beq     .nl
        move.w  #-WALKV,d1
        move.w  #1,s_dir(a0)
.nl     btst    #K_RIGHT,d3
        beq     .nr
        move.w  #WALKV,d1
        clr.w   s_dir(a0)
.nr     move.w  d1,s_vx(a0)
        move.w  d3,d4
        and.w   #KM_JUMP,d4     ; jump key held
        move.w  v_pkeys(a5),d5
        and.w   #KM_JUMP,d5
        move.w  s_vy(a0),d2
        tst.w   s_gnd(a0)
        beq     .air
        tst.w   d4
        beq     .mv
        tst.w   d5
        bne     .mv
        move.w  #-JUMPV,d2      ; take off
        clr.w   s_gnd(a0)
        bra     .mv
.air    addq.w  #GRAV,d2
        tst.w   d2
        bpl     .fall
        tst.w   d4              ; key released -> short jump
        bne     .cap
        cmp.w   #-SHORTV,d2
        bge     .cap
        move.w  #-SHORTV,d2
        bra     .cap
.fall   btst    #K_DOWN,d3
        beq     .nd
        cmp.w   #FASTV,d2
        bge     .cap
        move.w  #FASTV,d2
        bra     .cap
.nd     tst.w   d4              ; held -> glide
        beq     .cap
        cmp.w   #GLIDEV,d2
        ble     .cap
        move.w  #GLIDEV,d2
.cap    cmp.w   #MAXFALL,d2
        ble     .mv
        move.w  #MAXFALL,d2
.mv     move.w  d2,s_vy(a0)
        bsr     body_move
        ; animation
        addq.w  #1,s_anim(a0)
        moveq   #0,d0
        tst.w   s_gnd(a0)
        beq     .ina
        tst.w   s_vx(a0)
        beq     .img
        move.w  s_anim(a0),d0
        lsr.w   #1,d0
        and.w   #1,d0
        addq.w  #1,d0
        bra     .img
.ina    moveq   #3,d0
        tst.w   s_vy(a0)
        bmi     .img
        btst    #K_DOWN,d3
        bne     .img
        tst.w   d4
        beq     .img
        moveq   #4,d0
.img    add.w   d0,d0
        add.w   s_dir(a0),d0
        lsl.w   #8,d0
        lsl.w   #2,d0
        LEAX    spr_jack,a1
        add.w   d0,a1
        move.l  a1,s_img(a0)
        rts

;=====================================================================
; Enemies
;=====================================================================
update_enemies:
        tst.w   v_freeze(a5)
        beq     .nf
        subq.w  #1,v_freeze(a5) ; frozen: no new enemies either
        bra     .ns
.nf     subq.w  #1,v_spawn(a5)
        bgt     .ns
        move.w  v_spwin(a5),v_spawn(a5)
        bsr     spawn_enemy
.ns     lea     v_spr+s_size(a5),a0
        moveq   #MAXEN-1,d7
.l      tst.w   s_act(a0)
        beq     .n
        move.w  s_type(a0),d0
        cmp.w   #3,d0
        beq     .x
        tst.w   v_freeze(a5)
        bne     .f
        cmp.w   #1,d0
        beq     .w
        cmp.w   #5,d0
        bne.s   .sk
        bsr     hopper_upd
        bra     .n
.sk     bsr     seeker_upd
        bra     .n
.w      bsr     walker_upd
        bra     .n
.f      bsr     frozen_img
        bra     .n
.x      bsr     expl_upd
.n      lea     s_size(a0),a0
        dbra    d7,.l
        rts

frozen_img:                     ; a0 = enemy: ice picture, blinks shortly before thawing
        move.w  s_type(a0),d0
        LEAX    spr_walk_ice,a1
        cmp.w   #1,d0
        beq.s   .t
        LEAX    spr_hop_ice,a1
        cmp.w   #5,d0
        beq.s   .t
        LEAX    spr_seek_ice,a1
.t      cmp.w   #40,v_freeze(a5)
        bhs.s   .s
        btst    #2,v_freeze+1(a5)
        beq.s   .s
        LEAX    spr_walk,a1
        cmp.w   #1,d0
        beq.s   .s
        LEAX    spr_hop,a1
        cmp.w   #5,d0
        beq.s   .s
        LEAX    spr_seek,a1
.s      move.l  a1,s_img(a0)
        rts

expl_upd:                       ; a0 = exploding enemy
        addq.w  #1,s_anim(a0)
        move.w  s_anim(a0),d0
        cmp.w   #10,d0
        blo     .a
        clr.w   s_act(a0)       ; erased on the next frame
        rts
.a      lsr.w   #2,d0
        and.w   #1,d0
        lsl.w   #8,d0
        lsl.w   #2,d0
        LEAX    spr_expl,a1
        add.w   d0,a1
        move.l  a1,s_img(a0)
        rts

spawn_enemy:
        lea     v_spr+s_size(a5),a0
        moveq   #0,d1           ; number active
        sub.l   a1,a1           ; free slot
        moveq   #MAXEN-1,d0
.c      tst.w   s_act(a0)
        beq     .f
        addq.w  #1,d1
        bra     .cn
.f      cmp.l   #0,a1
        bne     .cn
        move.l  a0,a1
.cn     lea     s_size(a0),a0
        dbra    d0,.c
        cmp.w   v_maxen(a5),d1
        bge     .e
        cmp.l   #0,a1
        beq     .e
        move.l  a1,a0
        move.w  #s_size/2-1,d0
.z      clr.w   (a1)+
        dbra    d0,.z
        move.w  #1,s_act(a0)
        move.w  #1,s_type(a0)
        cmp.w   #5,v_round(a5)  ; from round 5 on: some hoppers
        blo.s   .wk
        bsr     rand
        and.w   #3,d0           ; 1 in 4 ...
        cmp.w   #9,v_round(a5)
        blo.s   .h4
        and.w   #1,d0           ; ... from round 9: 1 in 2
.h4     tst.w   d0
        bne.s   .wk
        move.w  #5,s_type(a0)
.wk     move.w  v_spwi(a5),d0
        addq.w  #1,v_spwi(a5)
        cmp.w   #2,d0
        blt     .s
        clr.w   v_spwi(a5)
.s      add.w   d0,d0
        move.l  v_spwt(a5),a1
        move.w  0(a1,d0.w),d0
        lsl.w   #4,d0
        move.w  d0,s_x(a0)
        move.w  #PF_CEIL<<4,s_y(a0)
        move.w  v_espd(a5),d1
        lea     v_spr(a5),a1
        cmp.w   s_x(a1),d0
        blt     .r
        neg.w   d1
.r      move.w  d1,s_vx(a0)
        LEAX    spr_walk,a1
        cmp.w   #5,s_type(a0)
        bne.s   .i
        LEAX    spr_hop,a1
.i      move.l  a1,s_img(a0)
.e      rts

hopper_upd:                     ; waits on the ground, then jumps towards Jack
        move.w  s_gnd(a0),d2    ; on the ground before the move?
        beq.s   .air
        clr.w   s_vx(a0)
        clr.w   s_vy(a0)
        subq.w  #1,s_dir(a0)    ; s_dir = waiting time
        bgt.s   .mv
        move.w  v_espd(a5),d1
        addq.w  #6,d1
        lea     v_spr(a5),a1
        move.w  s_x(a1),d0
        cmp.w   s_x(a0),d0
        bge.s   .rt
        neg.w   d1
.rt     move.w  d1,s_vx(a0)
        move.w  #-150,s_vy(a0)  ; jump about 90 pixels high
        clr.w   s_gnd(a0)
        moveq   #0,d2
        bra.s   .mv
.air    move.w  s_vy(a0),d0
        addq.w  #GRAV,d0
        cmp.w   #MAXFALL,d0
        ble.s   .a1
        moveq   #MAXFALL,d0
.a1     move.w  d0,s_vy(a0)
.mv     bsr     body_move
        btst    #0,s_flag+1(a0)
        beq.s   .nw
        neg.w   s_vx(a0)
.nw     tst.w   s_gnd(a0)
        beq.s   .img
        tst.w   d2
        bne.s   .img
        bsr     rand            ; just landed: wait 0.8 .. 1.4 s
        and.w   #15,d0
        add.w   #20,d0
        move.w  d0,s_dir(a0)
.img    LEAX    spr_hop,a1
        tst.w   s_gnd(a0)
        bne.s   .i
        lea     1024(a1),a1
.i      move.l  a1,s_img(a0)
        rts

walker_upd:                     ; walks on platforms, drops off edges
        move.w  s_vy(a0),d0
        tst.w   s_gnd(a0)
        bne     .g
        addq.w  #GRAV,d0
        cmp.w   #MAXFALL,d0
        ble     .s
        moveq   #MAXFALL,d0
        bra     .s
.g      moveq   #0,d0
.s      move.w  d0,s_vy(a0)
        bsr     body_move
        btst    #0,s_flag+1(a0)
        beq     .nw
        neg.w   s_vx(a0)
.nw     tst.w   s_gnd(a0)
        beq     .an
        move.w  s_y(a0),d0
        asr.w   #4,d0
        cmp.w   #FLOORY-SPRH,d0
        bne     .an
        move.w  #2,s_type(a0)   ; reached the floor -> becomes a flyer
        move.w  #-48,s_vy(a0)
        clr.w   s_gnd(a0)
        LEAX    spr_seek,a1
        move.l  a1,s_img(a0)
        rts
.an     addq.w  #1,s_anim(a0)
        move.w  s_anim(a0),d0
        lsr.w   #2,d0
        and.w   #1,d0
        lsl.w   #8,d0
        lsl.w   #2,d0
        LEAX    spr_walk,a1
        add.w   d0,a1
        move.l  a1,s_img(a0)
        rts

seeker_upd:                     ; flies towards Jack with inertia
        lea     v_spr(a5),a1
        move.w  v_espd(a5),d4
        addq.w  #6,d4           ; top speed
        move.w  s_vx(a0),d1
        move.w  s_x(a1),d0
        cmp.w   s_x(a0),d0
        blt     .l
        addq.w  #2,d1
        bra     .x
.l      subq.w  #2,d1
.x      bsr     .clamp
        move.w  d1,s_vx(a0)
        move.w  s_vy(a0),d1
        move.w  s_y(a1),d0
        cmp.w   s_y(a0),d0
        blt     .u
        addq.w  #2,d1
        bra     .y
.u      subq.w  #2,d1
.y      bsr     .clamp
        move.w  d1,s_vy(a0)
        ; move, bounce off edges
        move.w  s_x(a0),d0
        add.w   s_vx(a0),d0
        cmp.w   #XMIN<<4,d0
        bge     .x1
        move.w  #XMIN<<4,d0
        neg.w   s_vx(a0)
.x1     cmp.w   #XMAX<<4,d0
        ble     .x2
        move.w  #XMAX<<4,d0
        neg.w   s_vx(a0)
.x2     move.w  d0,s_x(a0)
        move.w  s_y(a0),d0
        add.w   s_vy(a0),d0
        cmp.w   #PF_CEIL<<4,d0
        bge     .y1
        move.w  #PF_CEIL<<4,d0
        neg.w   s_vy(a0)
.y1     cmp.w   #(FLOORY-SPRH)<<4,d0
        ble     .y2
        move.w  #(FLOORY-SPRH)<<4,d0
        neg.w   s_vy(a0)
.y2     move.w  d0,s_y(a0)
        addq.w  #1,s_anim(a0)
        move.w  s_anim(a0),d0
        lsr.w   #1,d0
        and.w   #1,d0
        lsl.w   #8,d0
        lsl.w   #2,d0
        LEAX    spr_seek,a1
        add.w   d0,a1
        move.l  a1,s_img(a0)
        rts
.clamp  cmp.w   d4,d1
        ble     .c1
        move.w  d4,d1
.c1     neg.w   d4
        cmp.w   d4,d1
        bge     .c2
        move.w  d4,d1
.c2     neg.w   d4
        rts

check_hits:                     ; Jack vs enemies (shrunk boxes)
        tst.w   v_inv(a5)
        beq.s   .ni
        subq.w  #1,v_inv(a5)
.ni     lea     v_spr(a5),a1
        move.w  s_x(a1),d2
        asr.w   #4,d2
        move.w  s_y(a1),d3
        asr.w   #4,d3
        lea     s_size(a1),a0
        moveq   #MAXEN-1,d7
.l      tst.w   s_act(a0)
        beq     .n
        move.w  s_type(a0),d1
        cmp.w   #3,d1           ; explosions are harmless
        beq     .n
        LEAX    hitwin,a2       ; per type: dx_min,dx_max,dy_min,dy_max (gfx.py)
        add.w   d1,d1
        add.w   d1,d1
        add.w   d1,a2
        move.w  s_x(a0),d0      ; dx = enemy - Jack in pixels
        asr.w   #4,d0
        sub.w   d2,d0
        move.b  (a2)+,d1
        ext.w   d1
        cmp.w   d1,d0
        blt     .n
        move.b  (a2)+,d1
        ext.w   d1
        cmp.w   d1,d0
        bgt     .n
        move.w  s_y(a0),d0      ; dy = enemy - Jack
        asr.w   #4,d0
        sub.w   d3,d0
        move.b  (a2)+,d1
        ext.w   d1
        cmp.w   d1,d0
        blt     .n
        move.b  (a2)+,d1
        ext.w   d1
        cmp.w   d1,d0
        bgt     .n
        tst.w   v_freeze(a5)
        bne     .c
        tst.w   v_inv(a5)       ; still protected
        bne     .n
        move.w  #1,v_dead(a5)
        bra     .n
.c      bsr     catch_enemy
.n      lea     s_size(a0),a0
        dbra    d7,.l
        rts

catch_enemy:                    ; a0 = frozen enemy touched by Jack
        movem.l d0-d3/d7/a0-a1,-(sp)
        move.w  #3,s_type(a0)   ; burst into an explosion
        clr.w   s_anim(a0)
        move.l  v_fpts(a5),d0
        bsr     add_score
        cmp.l   #$3200,v_fpts(a5)
        bhs     .m
        lea     v_fpts+4(a5),a0 ; double the BCD value: 200 400 800 1600 3200
        lea     v_fpts+4(a5),a1
        move    #4,ccr
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
        abcd    -(a0),-(a1)
.m      move.w  #1,v_hudd(a5)
        ifne    SOUND
        lea     snd_lit(pc),a3
        bsr     ipc
        endc
        movem.l (sp)+,d0-d3/d7/a0-a1
        rts

;---------------------------------------------------------------------
; Bonus items: 0 = extra life, 1 = freeze, 2 = blast
;---------------------------------------------------------------------
spawn_bonus:                    ; random kind
        movem.l d0-d2/a0-a1,-(sp)
        bsr     rand
        move.w  d0,d2
        and.w   #7,d0
        moveq   #0,d1           ; 2/8 extra life
        cmp.w   #2,d0
        blo     .k
        moveq   #1,d1           ; 3/8 freeze
        cmp.w   #5,d0
        blo     .k
        moveq   #2,d1           ; 3/8 blast
.k      bsr     spawn_bonus_k
        movem.l (sp)+,d0-d2/a0-a1
        rts

spawn_bonus_k:                  ; d1 = kind, d2 = random bits
        lea     BONUSSPR(a5),a0
        move.l  a0,a1
        move.w  #s_size/2-1,d0
.z      clr.w   (a1)+
        dbra    d0,.z
        move.w  #1,s_act(a0)
        move.w  #4,s_type(a0)
        move.w  d1,s_dir(a0)    ; kind
        move.w  d2,d0
        lsr.w   #3,d0
        and.w   #127,d0
        add.w   #40,d0
        lsl.w   #4,d0
        move.w  d0,s_x(a0)
        move.w  #(PF_CEIL+4)<<4,s_y(a0)
        moveq   #18,d0
        btst    #0,d2
        beq     .r
        neg.w   d0
.r      move.w  d0,s_vx(a0)
        move.w  #14,s_vy(a0)
        move.w  #BONUST,v_btime(a5)
        bsr     bonus_img
        ifne    SOUND
        lea     snd_bonus(pc),a3
        bsr     ipc
        endc
        rts

bonus_img:                      ; a0 = bonus: picture from kind and animation
        move.w  s_dir(a0),d0
        add.w   d0,d0
        move.w  s_anim(a0),d1
        lsr.w   #2,d1
        and.w   #1,d1
        add.w   d1,d0
        lsl.w   #8,d0
        lsl.w   #2,d0
        LEAX    spr_bonus,a1
        add.w   d0,a1
        move.l  a1,s_img(a0)
        rts

update_bonus:
        ifd     BONUSTEST       ; test build: bonus appears on Jack after 4 s
        addq.w  #1,v_btest(a5)
        cmp.w   #100,v_btest(a5)
        bne     .t
        moveq   #BONUSTEST-(BONUSTEST/10)*10,d1
        moveq   #0,d2
        bsr     spawn_bonus_k
        if      BONUSTEST<10    ; 10..12: bonus flies freely
        lea     v_spr(a5),a1
        lea     BONUSSPR(a5),a0
        move.w  s_x(a1),s_x(a0)
        move.w  s_y(a1),s_y(a0)
        endif
        ifd     CATCHTEST       ; test build: put the first enemy next to Jack
        lea     v_spr+s_size(a5),a0
        move.w  #1,s_act(a0)
        move.w  #2,s_type(a0)
        move.w  s_x(a1),d0
        add.w   #12<<4,d0
        move.w  d0,s_x(a0)
        move.w  s_y(a1),s_y(a0)
        clr.w   s_vx(a0)
        clr.w   s_vy(a0)
        endc
.t
        endc
        lea     BONUSSPR(a5),a0
        tst.w   s_act(a0)
        beq     .e
        subq.w  #1,v_btime(a5)
        bgt     .mv
        clr.w   s_act(a0)
.e      rts
.mv     move.w  s_x(a0),d0      ; bounce around, ignoring platforms
        add.w   s_vx(a0),d0
        cmp.w   #XMIN<<4,d0
        bge     .x1
        move.w  #XMIN<<4,d0
        neg.w   s_vx(a0)
.x1     cmp.w   #XMAX<<4,d0
        ble     .x2
        move.w  #XMAX<<4,d0
        neg.w   s_vx(a0)
.x2     move.w  d0,s_x(a0)
        move.w  s_y(a0),d0
        add.w   s_vy(a0),d0
        cmp.w   #PF_CEIL<<4,d0
        bge     .y1
        move.w  #PF_CEIL<<4,d0
        neg.w   s_vy(a0)
.y1     cmp.w   #(FLOORY-SPRH)<<4,d0
        ble     .y2
        move.w  #(FLOORY-SPRH)<<4,d0
        neg.w   s_vy(a0)
.y2     move.w  d0,s_y(a0)
        addq.w  #1,s_anim(a0)
        bsr     bonus_img
        clr.w   s_gnd(a0)       ; blink during the last 2 seconds
        cmp.w   #50,v_btime(a5)
        bhs     .h
        btst    #2,v_btime+1(a5)
        beq     .h
        move.w  #1,s_gnd(a0)
.h      lea     v_spr(a5),a1    ; touched by Jack?
        move.w  s_x(a0),d0
        sub.w   s_x(a1),d0
        bpl     .a
        neg.w   d0
.a      cmp.w   #10<<4,d0
        bge     .e2
        move.w  s_y(a0),d0
        sub.w   s_y(a1),d0
        bpl     .b
        neg.w   d0
.b      cmp.w   #13<<4,d0
        bge     .e2
        bra     bonus_hit
.e2     rts

bonus_hit:                      ; a0 = bonus item
        clr.w   s_act(a0)
        move.w  #1,v_hudd(a5)
        move.w  s_dir(a0),d0
        beq     .life
        subq.w  #1,d0
        beq     .frz
        lea     v_spr+s_size(a5),a0 ; blast: every enemy explodes, 100 each
        moveq   #MAXEN-1,d7
.l      tst.w   s_act(a0)
        beq     .n
        cmp.w   #3,s_type(a0)
        beq     .n
        move.w  #3,s_type(a0)
        clr.w   s_anim(a0)
        movem.l d7/a0,-(sp)
        move.l  #$100,d0
        bsr     add_score
        movem.l (sp)+,d7/a0
.n      lea     s_size(a0),a0
        dbra    d7,.l
        move.w  v_spwin(a5),v_spawn(a5)
        clr.w   v_freeze(a5)
        ifne    SOUND
        lea     snd_blast(pc),a3
        bsr     ipc
        endc
        rts
.frz    move.w  #FREEZET,v_freeze(a5)
        move.l  #$200,v_fpts(a5)
        ifne    SOUND
        lea     snd_frz(pc),a3
        bsr     ipc
        endc
        rts
.life   cmp.w   #9,v_lives(a5)
        bhs     .s
        addq.w  #1,v_lives(a5)
.s      ifne    SOUND
        lea     snd_life(pc),a3
        bsr     ipc
        endc
        rts

;=====================================================================
; Text / HUD (via QDOS windows)
;=====================================================================
opench:                         ; a0 = name -> a0 = channel
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #0,d3
        trap    #2
        moveq   #SD_BORDR,d0
        moveq   #0,d1
        moveq   #0,d2
        bsr     io3
        moveq   #SD_SETPA,d0
        moveq   #0,d1
        bsr     io3
        moveq   #SD_SETST,d0
        moveq   #0,d1
        bsr     io3
        moveq   #SD_SETIN,d0
        moveq   #7,d1
        bsr     io3
        moveq   #SD_SETSZ,d0
        moveq   #2,d1
        moveq   #0,d2
        bsr     io3
        rts                     ; (no clear: keeps the loading screen visible)
io3:    moveq   #-1,d3
        trap    #3
        rts

; print_centre: a1 = QDOS string, d4 = y, d5 = ink, d6 = size (0/1)
print_centre:
        movem.l d0-d7/a0-a4,-(sp)
        move.l  a1,a4           ; trap #3 smashes A1!
        move.l  v_msg(a5),a0
        moveq   #SD_SETSZ,d0
        moveq   #2,d1
        moveq   #0,d2
        cmp.w   #1,d6
        bne     .s
        moveq   #3,d1
        moveq   #1,d2
.s      bsr     io3
        moveq   #SD_SETIN,d0
        move.w  d5,d1
        bsr     io3
        move.w  (a4)+,d7
        move.w  #TXTX,d1        ; size 2: small, left aligned at TXTX
        cmp.w   #2,d6
        beq     .p
        move.w  #CW0,d1
        tst.w   d6
        beq     .w
        move.w  #CW1,d1
.w      mulu    d7,d1
        neg.w   d1
        add.w   #512,d1
        asr.w   #1,d1
.p      move.w  d4,d2
        moveq   #SD_PIXP,d0
        bsr     io3
        moveq   #IO_SSTRG,d0
        move.w  d7,d2
        move.l  a4,a1
        bsr     io3
        movem.l (sp)+,d0-d7/a0-a4
        rts

hud_draw:
        movem.l d0-d7/a0-a3,-(sp)
        clr.w   v_hudd(a5)
        lea     hudtpl(pc),a0
        tst.w   v_lang(a5)
        beq.s   .de
        lea     32(a0),a0
.de     lea     v_str(a5),a1
        moveq   #31,d0
.c      move.b  (a0)+,(a1)+
        dbra    d0,.c
        lea     v_str+6(a5),a1
        lea     v_score+1(a5),a0
        moveq   #2,d1
.d      move.b  (a0)+,d0
        move.b  d0,d2
        lsr.b   #4,d2
        add.b   #'0',d2
        move.b  d2,(a1)+
        and.b   #$0f,d0
        add.b   #'0',d0
        move.b  d0,(a1)+
        dbra    d1,.d
        moveq   #0,d0
        move.w  v_round(a5),d0
        divu    #10,d0
        add.b   #'0',d0
        move.b  d0,v_str+20(a5)
        swap    d0
        add.b   #'0',d0
        move.b  d0,v_str+21(a5)
        move.w  v_lives(a5),d0
        add.b   #'0',d0
        move.b  d0,v_str+30(a5)
        ifne    DEBUG
        move.w  v_lagmx(a5),d0
        add.b   #'0',d0
        move.b  d0,v_str+31(a5)
        endc
        move.l  v_hud(a5),a0
        moveq   #SD_SETIN,d0
        moveq   #6,d1
        bsr     io3
        moveq   #SD_PIXP,d0
        moveq   #0,d1
        moveq   #3,d2
        bsr     io3
        moveq   #IO_SSTRG,d0
        moveq   #32,d2
        lea     v_str(a5),a1
        bsr     io3
        movem.l (sp)+,d0-d7/a0-a3
        rts

build_round:                    ; v_str = QDOS string "ROUND nn"
        lea     v_str(a5),a0
        move.w  #8,(a0)+
        lea     s_round(pc),a1
        tst.w   v_lang(a5)
        beq.s   .de
        addq.l  #6,a1
.de     moveq   #5,d0
.c      move.b  (a1)+,(a0)+
        dbra    d0,.c
        moveq   #0,d0
        move.w  v_round(a5),d0
        divu    #10,d0
        add.b   #'0',d0
        move.b  d0,(a0)+
        swap    d0
        add.b   #'0',d0
        move.b  d0,(a0)+
        rts

        ifne    DEBUG
dbg_lag:                        ; measures max frames per loop (excluding HUD output)
        tst.w   v_dbgs(a5)
        beq     .m
        clr.w   v_dbgs(a5)
        bra     .n
.m      move.w  v_lag(a5),d0
        cmp.w   v_lagmx(a5),d0
        ble     .n
        move.w  d0,v_lagmx(a5)
.n      addq.w  #1,v_dbgc(a5)
        cmp.w   #100,v_dbgc(a5)
        blt     .e
        clr.w   v_dbgc(a5)
        bsr     hud_draw
        clr.w   v_lagmx(a5)
        move.w  #1,v_dbgs(a5)
.e      rts
        endc

;=====================================================================
; Data
;=====================================================================
kr1:    dc.b    9,1,0,0,0,0,1,2         ; IPC: KEYROW(1)
kr0:    dc.b    9,1,0,0,0,0,0,2         ; IPC: KEYROW(0)
        ifne    SOUND
snd_bomb: dc.b  $0a,8,0,0,$aa,$aa,12,12,0,0,$20,$03,0,0,1
        even
snd_lit:  dc.b  $0a,8,0,0,$aa,$aa,4,8,$40,0,$00,$08,$11,0,1
        even
snd_die:  dc.b  $0a,8,0,0,$aa,$aa,40,180,$80,0,$00,$40,$f1,0,1
        even
snd_bonus: dc.b $0a,8,0,0,$aa,$aa,30,6,$10,0,$00,$06,$31,0,1
        even
snd_life: dc.b  $0a,8,0,0,$aa,$aa,20,2,$08,0,$00,$10,$21,0,1
        even
snd_frz:  dc.b  $0a,8,0,0,$aa,$aa,2,30,$08,0,$00,$10,$21,0,1
        even
snd_blast: dc.b $0a,8,0,0,$aa,$aa,120,200,$10,0,$00,$18,$f1,$ff,1
        even
snd_kill: dc.b  $0b,0,0,0,0,0,1
        even
        endc

hudname: qstr   'con_512x16a0x0'
msgname: qstr   'con_512x236a0x20'
LQ      macro                   ; German / English string pair
        qstr    \1
        qstr    \2
        endm

hudtpl: dc.b    'SCORE 000000  RUNDE 00  LEBEN 0 '
        dc.b    'SCORE 000000  ROUND 00  LIVES 0 '
s_round: dc.b   'RUNDE ROUND '
        even
s_ready: LQ     'LOS GEHTS!','GET READY!'
s_ouch:  LQ     'AUTSCH!','OUCH!'
s_over:  LQ     'SPIEL VORBEI','GAME OVER'
s_clear: LQ     'RUNDE GESCHAFFT!','ROUND CLEAR!'
s_pause: LQ     'PAUSE','PAUSED'
s_litb:  LQ     'FEUERBOMBEN: ','LIT BOMBS: '
mn_hi:   LQ     'HIGHSCORE ','HIGH SCORE '
s_rank:  LQ     'PLATZ ','RANK '
s_key:   LQ     ' TASTE DRUECKEN ',' PRESS ANY KEY '

lvlnames:
        LQ      'DIE STADT','THE CITY'
        LQ      'DIE BERGE','THE MOUNTAINS'
        LQ      'DIE WUESTE','THE DESERT'
        LQ      'DER HAFEN','THE HARBOUR'
        LQ      'DIE BURG','THE CASTLE'
        LQ      'DER WALD','THE FOREST'
        LQ      'DIE MONDBASIS','THE MOON BASE'
        LQ      'DIE ARKTIS','THE ARCTIC'
        LQ      'DER VULKAN','THE VOLCANO'

mn_items:
        LQ      'SPIEL STARTEN','START GAME'
        LQ      'ANLEITUNG','HOW TO PLAY'
        LQ      'HIGHSCORES','HIGH SCORES'
        LQ      'SCHWIERIGKEIT: NORMAL','DIFFICULTY: NORMAL'
        LQ      'MUSIK: AN','MUSIC: ON'
        LQ      'SPRACHE: DEUTSCH','LANGUAGE: ENGLISH'
        LQ      'CREDITS','CREDITS'
        LQ      'ENDE','QUIT'
mn_easy: LQ     'SCHWIERIGKEIT: LEICHT','DIFFICULTY: EASY'
mn_moff: LQ     'MUSIK: AUS','MUSIC: OFF'

mn_title:
        dc.w    18,6,1
        LQ      'FUSE RUNNER','FUSE RUNNER'
        dc.w    44,3,0
        LQ      'EIN QL-SPIEL IN 68000 ASSEMBLER','A QL GAME IN 68000 ASSEMBLER'
        dc.w    214,4,0
        LQ      'JOYSTICK/CURSOR + LEERTASTE','JOYSTICK/CURSOR KEYS + SPACE'
        dc.w    -1

pg_help:
        dc.w    6,6,1
        LQ      'ANLEITUNG','HOW TO PLAY'
        dc.w    34,5,0
        LQ      'LINKS/RECHTS   LAUFEN','LEFT/RIGHT      WALK'
        dc.w    46,5,0
        LQ      'HOCH/LEERTASTE SPRINGEN','UP/SPACE        JUMP'
        dc.w    58,5,0
        LQ      'LANG HALTEN = HOHER SPRUNG','HOLD LONGER = HIGHER JUMP'
        dc.w    70,5,0
        LQ      'IM FALLEN HALTEN = GLEITEN','HOLD WHILE FALLING = GLIDE'
        dc.w    82,5,0
        LQ      'RUNTER = SCHNELL FALLEN','DOWN = DROP FAST'
        dc.w    94,5,0
        LQ      'ENTER = PAUSE   ESC = MENUE','ENTER = PAUSE   ESC = MENU'
        dc.w    112,4,0
        LQ      'SAMMLE ALLE BOMBEN EIN!','COLLECT ALL THE BOMBS!'
        dc.w    124,6,0
        LQ      'BRENNENDE BOMBE = 200 PUNKTE','LIT BOMB = 200 POINTS'
        dc.w    136,6,0
        LQ      'IN FOLGE: 500 BONUS JE BOMBE','IN SEQUENCE: 500 BONUS EACH'
        dc.w    156,7,2
        LQ      'HERZ = EXTRALEBEN','HEART = EXTRA LIFE'
        dc.w    174,7,2
        LQ      'FLOCKE = GEGNER EINFRIEREN','SNOWFLAKE = FREEZE ENEMIES'
        dc.w    192,7,2
        LQ      'STERN = GEGNER EXPLODIEREN','STAR = ENEMIES EXPLODE'
        dc.w    216,3,0
        LQ      'EXTRALEBEN ALLE 20000 PUNKTE','EXTRA LIFE EVERY 20000 POINTS'
        dc.w    -1

pg_cred:
        dc.w    10,6,1
        LQ      'FUSE RUNNER','FUSE RUNNER'
        dc.w    36,3,0
        LQ      'EIN QL-SPIEL IN 68000 ASSEMBLER','A QL GAME IN 68000 ASSEMBLER'
        dc.w    70,5,0
        LQ      'IDEE','IDEA'
        dc.w    84,7,1
        LQ      'JUNGSI','JUNGSI'
        dc.w    116,5,0
        LQ      'CODE','CODE'
        dc.w    130,7,1
        LQ      'CLAUDE UND JUNGSI','CLAUDE AND JUNGSI'
        dc.w    166,4,0
        LQ      'MEHR RETRO-COMPUTING AUF','MORE RETRO COMPUTING AT'
        dc.w    180,6,1
        LQ      'WWW.JUNGSI.DE','WWW.JUNGSI.DE'
        dc.w    218,7,0
        LQ      '(C) 2026','(C) 2026'
        dc.w    -1

pg_scores:
        dc.w    12,6,1
        LQ      'HIGHSCORES','HIGH SCORES'
        dc.w    200,3,0
        LQ      'L = LEICHT','E = EASY'
        dc.w    212,3,0
        LQ      'TASTE DRUECKEN','PRESS A KEY'
        dc.w    -1

pg_name:
        dc.w    20,6,1
        LQ      'NEUER HIGHSCORE!','NEW HIGH SCORE!'
        dc.w    56,7,0
        LQ      'GIB DEINEN NAMEN EIN','ENTER YOUR NAME'
        dc.w    170,5,0
        LQ      'TIPPEN ODER HOCH/RUNTER','TYPE OR USE UP/DOWN'
        dc.w    182,5,0
        LQ      'RECHTS/LEERTASTE: WEITER','RIGHT/SPACE: NEXT'
        dc.w    194,5,0
        LQ      'LINKS: ZURUECK','LEFT: BACK'
        dc.w    206,5,0
        LQ      'ENTER: FERTIG','ENTER: DONE'
        dc.w    -1

; QL key matrix: KEYROW(row) bit b = key (verified with sQLux and the
; MiSTer core): 0 = no character
ktab:   dc.b    0,0,'5',0,0,0,'4','7'               ; F4 F1 5 F2 F3 F5 4 7
        dc.b    0,0,0,0,0,0,0,0                     ; enter, cursor, esc, space
        dc.b    0,'Z','.','C','B',0,'M',0           ; ] z . c b pound m '
        dc.b    0,0,'K','S','F',0,'G',0             ; [ caps k s f = g ;
        dc.b    'L','3','H','1','A','P','D','J'
        dc.b    '9','W','I',0,'R','-','Y','O'       ; tab
        dc.b    '8','2','6','Q','E','0','T','U'
        dc.b    0,0,0,'X','V',0,'N',0               ; shift ctrl alt / ,
charset: dc.b   ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-!'
CHARN   equ     *-charset
        even

hs_names:
        qstr    'fuse_hi'
        qstr    'win1_fuse_hi'
        qstr    'flp1_fuse_hi'
        qstr    'mdv1_fuse_hi'

hs_default:
        dc.l    'FRH3'
        dc.w    0                       ; language: German
        dc.w    0                       ; difficulty: normal
        dc.w    0                       ; music: on
        dc.l    $25000
        dc.w    6
        dc.b    'JUNGSI    '
        dc.l    $20000
        dc.w    5
        dc.b    'CLAUDE    '
        dc.l    $15000
        dc.w    4
        dc.b    'SINCLAIR  '
        dc.l    $12000
        dc.w    4
        dc.b    'MINERVA   '
        dc.l    $10000
        dc.w    3
        dc.b    'QDOS      '
        dc.l    $8000
        dc.w    3
        dc.b    'SUPERBASIC'
        dc.l    $6000
        dc.w    2
        dc.b    'MICRODRIVE'
        dc.l    $4000
        dc.w    2
        dc.b    'ZX8301    '
        dc.l    $3000
        dc.w    1
        dc.b    'IPC8049   '
        dc.l    $2000
        dc.w    1
        dc.b    'QL        '

iconys: dc.w    156,174,192

        include "gfx.inc"
        include "music.inc"
        include "splash.inc"
        include "levels.inc"
        include "bgdata.inc"
        end
