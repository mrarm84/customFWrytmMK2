        | Mod 0020 - CTRL IN and AUDIO IN trigger tracks.
        |
        | CTRL IN 1 plays T1 (pad 1, BD), CTRL IN 2 plays T2 (pad 2, SD), in
        | any CONTROL INPUT mode, OFF included. AUDIO IN L plays T11, AUDIO IN
        | R plays T12, while SETTINGS > AUDIO ROUTING > AUDIO IN is TRIG or
        | TRIG INV; at SAMPLE (the default) the audio inputs are left alone.
        | A rising gate plays the track as an Overbridge note does, note 60
        | (the track's own pitch) at velocity 127, once a gate: the note-off
        | follows len_ms later (mod.toml), whatever the gate's length.
        |
        | Detection, in the audio interrupt just after adc_pedal_update
        | (0x40120e9e, every 32 samples, 0.67 ms).
        |   CTRL IN: the port's raw converter result (ADRSLT, 0xfc094012 +
        |   2p, the value adc_pedal_update smooths) against ON_MV and OFF_MV
        |   turned into raw units by stock's own millivolt conversion
        |   (0x4013f3fa, CTRL IN 1's calibration). On above 1.0 V, off below
        |   0.5 V.
        |   AUDIO IN: words 10 and 11 of the receive buffer (0x80007440, Q31,
        |   refilled at 0x40121358, later in the interrupt: so this reads the
        |   block before, 0.67 ms late). Every AIN_STEP-th frame's sample is
        |   taken, the block's largest (TRIG) or most negative (TRIG INV),
        |   >> 16, against ain_on / ain_off percent of full scale. The
        |   inputs are AC-coupled audio inputs: a gate shows as a spike at
        |   each edge, decaying, of the gate's polarity at the rising edge
        |   and the other at the falling one; TRIG takes the positive ones.
        |   If a gate plays at its end rather than its start, use TRIG INV.
        | Each edge bumps a per-port counter and signals the MIDI task's
        | semaphore (0x418fd874) with the kernel's signal (0x40000d0a),
        | masked as the queue post masks it - the same path adc_pedal_update's
        | own queue post takes from this interrupt.
        |
        | Playing, in the MIDI task (0x40082cac) at the top of its loop
        | (0x40082d12, just before it waits on that semaphore): every new edge
        | is played with stock's note_on (0x40083ed4) or note_off (0x4008419e),
        | as Overbridge's note path calls them (0x401030aa): source 2, so the
        | note is handled as an external one. Calling them from the task that
        | already calls them for MIDI notes keeps the engine's note lists out
        | of the interrupt.
        |
        | The AUDIO IN item: appended to AudioRoutingMenuView's list after
        | every other item (DAC SUM, DIST FILTER), over the list's epilogue
        | (0x400d902c), the view's vtable +28 (the cursor restore) then called
        | again so a cursor left on AUDIO IN comes back to it. Its value is
        | device-wide, in the persisted gap at 0x405c8ea0 (tag AINT, version,
        | mode), clear of 0019's DSTF record (0x405c8e90..0x405c8e9b).

        .include "symbols.inc"

        .equ    ISR_RESUME,     0x40120ea4        | past the displaced lea
        .equ    ADRSLT,         0xfc094012        | ports' raw results, words
        .equ    MV_RAW,         0x4013f3fa        | (port, mV) -> raw, as the CV levels
        .equ    ON_MV,          1000              | the gate: on above 1.0 V
        .equ    OFF_MV,         500               | off below 0.5 V
        .equ    PORTS,          4                 | CTRL IN 1, 2, AUDIO IN L, R
        .equ    CTRL_PORTS,     2

        .equ    RXBUF,          0x80007440        | receive buffer, 48 B a frame
        .equ    RX_AIN,         40                | word 10: AUDIO IN L, 11 R
        .equ    RXSTRIDE,       48
        .equ    FRAMES,         32
        .equ    AIN_STEP,       4                 | every 4th frame: 8 a block
        .equ    AIN_ON,         (P_AIN_ON * 32768) / 100
        .equ    AIN_OFF,        (P_AIN_OFF * 32768) / 100

        .equ    MIDI_SEM,       0x418fd874        | the MIDI task's semaphore
        .equ    SEM_SIGNAL,     0x40000d0a        | (sem), interrupts masked
        .equ    TASK_RESUME,    0x40082d18        | past the displaced pea
        .equ    NOTE_ON,        0x40083ed4        | (track, note, vel, src, 0, -1, 0)
        .equ    NOTE_OFF,       0x4008419e        | (track, note, src)
        .equ    NOTE,           60                | the track's own pitch
        .equ    VEL,            127
        .equ    SRC,            2                 | as Overbridge

        | AudioRoutingMenuView's list, as 0013 and 0019 build their items.
        .equ    MGR_LABEL,      0x400d8aca
        .equ    MGR_DRAW,       0x400d8b1c
        .equ    TEXT_WIDTH,     0x40071b86        | (font, -1, std::string *) -> px
        .equ    MENU_FONT,      0x4027a6c8
        .equ    VIEW_INVALIDATE, 0x40078514       | (view + 56)

        | The AUDIO IN setting, device-wide.
        .equ    CFG,            0x405c8ea0
        .equ    CFG_TAG,        0x41494e54        | "AINT"
        .equ    CFG_VER,        1
        .equ    CFG_MODE,       5                 | 0 SAMPLE, 1 TRIG, 2 TRIG INV
        .equ    MODES,          3

        | One trig a gate (2026-11-13): a rising edge plays the track once;
        | the note-off follows LEN_BLOCKS later whatever the gate does, so a
        | long gate no longer holds the note and the falling edge only re-arms.
        | After a trig the port is not looked at for HOLD_BLOCKS, so a bouncing
        | edge cannot trig twice.
        .equ    LEN_BLOCKS,     (P_LEN_MS * 3) / 2   | 0.667 ms a block
        .equ    HOLD_BLOCKS,    3                 | 2 ms

        | Run-time state, cvt_state + :
        .equ    S_GATE,         0                 | + p: gate on
        .equ    S_ON,           4                 | + p: trigs, counted
        .equ    S_OFF,          8                 | + p: note-offs due, counted
        .equ    S_ON_DONE,      12                | + p: the task's copies
        .equ    S_OFF_DONE,     16
        .equ    S_PLAYING,      20                | + p: track playing, -1 none
        .equ    S_HOLD,         24                | + p: blocks left not looking
        .equ    S_LEN,          28                | + 2p: blocks to the note-off

        .if     LEN_BLOCKS < 1
        .error  "0020-cv-trig: len_ms must be 1 or more"
        .endif
        .if     LEN_BLOCKS > 65535
        .error  "0020-cv-trig: len_ms too long"
        .endif
        .if     P_AIN_OFF >= P_AIN_ON
        .error  "0020-cv-trig: ain_off must be below ain_on"
        .endif
        .if     P_AIN_ON > 99
        .error  "0020-cv-trig: ain_on must be 1 .. 99"
        .endif
        .if     P_AIN_OFF < 1
        .error  "0020-cv-trig: ain_off must be 1 or more"
        .endif

        .text

        | cvt_count(d1 = the counter's offset + port, a2 = state): one more,
        | and an edge to signal. Uses d0.
        .macro  cvt_count
        mvz.b   (%a2,%d1.l),%d0
        addq.l  #1,%d0
        move.b  %d0,(%a2,%d1.l)
        moveq   #1,%d6
        .endm

        | ------------------------------------------------------------------
        | cvt_isr: over `lea 0x800067de,%a4`, after adc_pedal_update has
        | returned and its arguments are popped. d0, d1, a0 and a1 are written
        | before they are read on the way to the next call, so they are free.
        | ------------------------------------------------------------------
        .align  2
cvt_isr:
        lea     -24(%sp),%sp
        movem.l %d2-%d6/%a2,(%sp)
        lea     cvt_state,%a2
        moveq   #0,%d6                            | an edge to signal
        pea     ON_MV                             | the thresholds, raw, by CTRL
        clr.l   -(%sp)                            | IN 1's conversion for both
        jsr     MV_RAW                            | ports: the jacks are alike,
        addq.l  #8,%sp                            | and CTRL IN 2's own never let
        move.l  %d0,%d3                           | a gate trig it on the unit
        asr.l   #3,%d3                            | (2026-11-13)
        pea     OFF_MV
        clr.l   -(%sp)
        jsr     MV_RAW
        addq.l  #8,%sp
        move.l  %d0,%d4
        asr.l   #3,%d4
        moveq   #0,%d2                            | port
1:      mvz.w   S_LEN(%a2,%d2.l*2),%d0            | the note-off countdown
        beq.s   2f
        subq.l  #1,%d0
        move.w  %d0,S_LEN(%a2,%d2.l*2)
        bne.s   2f
        moveq   #S_OFF,%d1
        add.l   %d2,%d1
        cvt_count
2:      mvz.b   S_HOLD(%a2,%d2.l),%d0             | just trigged: not looking
        beq.s   3f
        subq.l  #1,%d0
        move.b  %d0,S_HOLD(%a2,%d2.l)
        bra.w   8f
3:      moveq   #CTRL_PORTS,%d0
        cmp.l   %d0,%d2
        bge.s   5f
        lea     ADRSLT,%a0                        | CTRL IN
        mvs.w   (%a0,%d2.l*2),%d0                 | signed, as adc_pedal_update
        asr.l   #3,%d0                            | reads it, and scaled as it is
        move.l  %d3,%a1                           | on
        move.l  %d4,%d5                           | off
        bra.s   6f
5:      bsr.w   ain_level                         | AUDIO IN
        bpl.s   7f
        moveq   #1,%d0                            | SAMPLE: held as if high, so
        move.b  %d0,S_GATE(%a2,%d2.l)             | TRIG first waits for a quiet
        bra.s   8f                                | input
7:      move.w  #AIN_ON,%a1
        move.l  #AIN_OFF,%d5
6:      tst.b   S_GATE(%a2,%d2.l)
        bne.s   4f
        cmp.l   %a1,%d0                           | off: on above the on level
        ble.s   8f
        moveq   #1,%d0
        move.b  %d0,S_GATE(%a2,%d2.l)
        moveq   #HOLD_BLOCKS,%d0
        move.b  %d0,S_HOLD(%a2,%d2.l)
        move.l  #LEN_BLOCKS,%d0
        move.w  %d0,S_LEN(%a2,%d2.l*2)
        moveq   #S_ON,%d1
        add.l   %d2,%d1
        cvt_count
        bra.s   8f
4:      cmp.l   %d5,%d0                           | on: re-armed below the off
        bge.s   8f                                | level
        clr.b   S_GATE(%a2,%d2.l)
8:      addq.l  #1,%d2
        moveq   #PORTS,%d0
        cmp.l   %d0,%d2
        blt.w   1b
        tst.l   %d6
        beq.s   9f
        move.w  %sr,%d5
        move.w  #0x2700,%sr
        pea     MIDI_SEM
        jsr     SEM_SIGNAL
        addq.l  #4,%sp
        move.w  %d5,%sr
9:      movem.l (%sp),%d2-%d6/%a2
        lea     24(%sp),%sp
        lea     0x800067de,%a4                    | displaced
        jmp     ISR_RESUME

        | ain_level(d2 = port, 2 or 3) -> d0 = the input's level for the
        | gate, >= 0, N clear; or d0 = -1, N set, at SAMPLE. TRIG: the
        | block's largest sample, TRIG INV: the negated most negative one,
        | Q31 >> 16. Uses d0, d1, a0.
        .align  2
ain_level:
        bsr.w   cfg_mode
        bne.s   1f
        moveq   #-1,%d0
        rts
1:      lea     -12(%sp),%sp
        movem.l %d3-%d5,(%sp)
        move.l  %d0,%d5                           | the mode
        lea     RXBUF + RX_AIN - 8,%a0            | + 4 * port
        move.l  %d2,%d0
        lsl.l   #2,%d0
        add.l   %d0,%a0
        moveq   #0,%d0                            | largest
        moveq   #0,%d4                            | most negative
        moveq   #FRAMES / AIN_STEP,%d1
2:      move.l  (%a0),%d3
        lea     RXSTRIDE * AIN_STEP(%a0),%a0
        cmp.l   %d0,%d3
        ble.s   3f
        move.l  %d3,%d0
3:      cmp.l   %d4,%d3
        bge.s   4f
        move.l  %d3,%d4
4:      subq.l  #1,%d1
        bne.s   2b
        moveq   #16,%d1
        subq.l  #1,%d5
        beq.s   5f
        asr.l   %d1,%d4                           | TRIG INV
        neg.l   %d4
        move.l  %d4,%d0
        bra.s   6f
5:      asr.l   %d1,%d0                           | TRIG
6:      movem.l (%sp),%d3-%d5
        lea     12(%sp),%sp
        tst.l   %d0
        rts

        | ------------------------------------------------------------------
        | cvt_task: the MIDI task's loop top, over `pea 0x418fd874` (its wait's
        | argument), re-emitted. d0, d1, a0 and a1 are dead here; d2 is set
        | right after. Each port's due note-off releases the track its last
        | trig played; each new trig is a note_on of its track.
        | ------------------------------------------------------------------
        .align  2
cvt_task:
        lea     -12(%sp),%sp
        movem.l %d2-%d3/%a2,(%sp)
        lea     cvt_state,%a2
        moveq   #0,%d2                            | port
1:      mvz.b   S_OFF(%a2,%d2.l),%d0              | a due note-off first, so a
        mvz.b   S_OFF_DONE(%a2,%d2.l),%d1         | trig pending with it is not
        cmp.l   %d1,%d0                           | cut by it
        beq.s   3f
        move.b  %d0,S_OFF_DONE(%a2,%d2.l)
        bsr.w   cvt_release
3:      mvz.b   S_ON(%a2,%d2.l),%d0
        mvz.b   S_ON_DONE(%a2,%d2.l),%d1
        cmp.l   %d1,%d0
        beq.s   4f
        move.b  %d0,S_ON_DONE(%a2,%d2.l)
        mvz.b   cvt_dest(%pc,%d2.l),%d3           | the track
        bsr.w   cvt_release                       | one note per port
        move.b  %d3,S_PLAYING(%a2,%d2.l)
        clr.l   -(%sp)
        pea     -1
        clr.l   -(%sp)
        pea     SRC
        pea     VEL
        pea     NOTE
        move.l  %d3,-(%sp)
        jsr     NOTE_ON
        lea     28(%sp),%sp
4:      addq.l  #1,%d2
        moveq   #PORTS,%d0
        cmp.l   %d0,%d2
        blt.s   1b
        movem.l (%sp),%d2-%d3/%a2
        lea     12(%sp),%sp
        pea     MIDI_SEM                          | displaced
        jmp     TASK_RESUME

        | cvt_dest[port]: the track each port plays, 0-based: T1, T2, T11,
        | T12.
cvt_dest:
        .byte   0, 1, 10, 11

        | cvt_release(d2 = port, a2 = state): note_off for the track the
        | port is playing, if any. Keeps d2, d3, a2.
        .align  2
cvt_release:
        mvs.b   S_PLAYING(%a2,%d2.l),%d0
        bmi.s   9f
        moveq   #-1,%d1
        move.b  %d1,S_PLAYING(%a2,%d2.l)
        pea     SRC
        pea     NOTE
        move.l  %d0,-(%sp)
        jsr     NOTE_OFF
        lea     12(%sp),%sp
9:      rts

        | ------------------------------------------------------------------
        | The AUDIO IN setting.
        |
        | cfg_mode -> d0 = the mode, 0..2, Z set for SAMPLE (also when there
        | is no record). Uses d0, a0.
        | ------------------------------------------------------------------
        .align  2
cfg_mode:
        lea     CFG,%a0
        move.l  (%a0),%d0
        cmp.l   #CFG_TAG,%d0
        bne.s   1f
        mvz.b   4(%a0),%d0
        cmp.l   #CFG_VER,%d0
        bne.s   1f
        mvz.b   CFG_MODE(%a0),%d0
        cmp.l   #MODES,%d0
        bcs.s   2f
1:      moveq   #0,%d0
2:      tst.l   %d0
        rts

        | cfg_set(d1 = mode): into the record, a fresh one first if there
        | is none - the setting first and the tag last, so the interrupt
        | never reads a tag over unwritten bytes. Uses d0, a0.
        .align  2
cfg_set:
        lea     CFG,%a0
        move.l  (%a0),%d0
        cmp.l   #CFG_TAG,%d0
        bne.s   1f
        mvz.b   4(%a0),%d0
        cmp.l   #CFG_VER,%d0
        beq.s   2f
1:      clr.l   (%a0)
        moveq   #0,%d0
        move.l  %d0,4(%a0)
        moveq   #CFG_VER,%d0
        move.b  %d0,4(%a0)
        move.b  %d1,CFG_MODE(%a0)
        move.l  #CFG_TAG,%d0
        move.l  %d0,(%a0)
        rts
2:      move.b  %d1,CFG_MODE(%a0)
        rts

        | ain_draw(functor, -, canvas, x, y): SAMPLE, TRIG or TRIG INV,
        | right-aligned at x + 19, as DAC SUM's and DIST FILTER's.
        .align  2
ain_draw:
        lea     -32(%sp),%sp
        movem.l %d2-%d7,(%sp)                     | the string at +24, its allocator +28
        move.l  44(%sp),%d5                       | canvas
        move.l  48(%sp),%d6
        add.l   #19,%d6                           | right edge
        move.l  52(%sp),%d7
        addq.l  #2,%d7                            | y
        lea     24(%sp),%a0
        move.l  %a0,%d3
        lea     28(%sp),%a0
        move.l  %a0,%d4
        bsr.w   cfg_mode
        lea     txt_modes,%a0
        move.l  (%a0,%d0.l*4),%d2
        move.l  %d4,-(%sp)
        move.l  %d2,-(%sp)
        move.l  %d3,-(%sp)
        jsr     std_string_from_cstr
        move.l  %d3,-(%sp)
        pea     -1
        pea     MENU_FONT
        jsr     TEXT_WIDTH
        sub.l   %d0,%d6
        move.l  %d3,-(%sp)
        jsr     std_string_dtor
        move.l  %d2,-(%sp)                        | the text as format, no %
        move.l  %d2,-(%sp)                        | and as width
        clr.l   -(%sp)
        pea     -1
        move.l  %d7,-(%sp)
        move.l  %d6,-(%sp)
        pea     MENU_FONT
        move.l  %d5,-(%sp)
        jsr     text_draw
        lea     60(%sp),%sp
        movem.l (%sp),%d2-%d7
        lea     32(%sp),%sp
        rts

        .align  2
txt_modes:
        .long   txt_sample, txt_trig, txt_inv
txt_ain:
        .asciz  "AUDIO IN"
txt_sample:
        .asciz  "SAMPLE"
txt_trig:
        .asciz  "TRIG"
txt_inv:
        .asciz  "TRIG INV"

        | ------------------------------------------------------------------
        | State, written at run time: gates, edge counters, the task's
        | copies, and the track each port plays (-1 none).
        | ------------------------------------------------------------------
        .align  2
cvt_state:
        | Power-up: each port starts as if a gate were high, so it must fall
        | below its off level before its first trig, and is not read at all
        | for its first 255 blocks (170 ms) while the converter settles;
        | before, CTRL IN 1 crossed ON_MV once at start-up and T1 played
        | (2026-11-13).
        .byte   1, 1, 1, 1                        | S_GATE
        .byte   0, 0, 0, 0                        | S_ON
        .byte   0, 0, 0, 0                        | S_OFF
        .byte   0, 0, 0, 0                        | S_ON_DONE
        .byte   0, 0, 0, 0                        | S_OFF_DONE
        .byte   -1, -1, -1, -1                    | S_PLAYING
        .byte   255, 255, 255, 255                | S_HOLD
        .word   0, 0, 0, 0                        | S_LEN

        | ------------------------------------------------------------------
        | cave24's tail (.aim): the AUDIO IN item, UI context only. Calls
        | back into .text by jsr: the two pools are too far apart for bsr.w.
        | ------------------------------------------------------------------
        .section .aim,"ax"

        | ------------------------------------------------------------------
        | ain_menu: AudioRoutingMenuView's item list, over its epilogue's
        | `moveml %sp@(36),%d2-%d7/%a2-%fp`, just after the view's vtable
        | +28 call (view, cursor, 2). Its three arguments are taken back, so
        | the stack is at the depth the items are built at, AUDIO IN is
        | appended with DIST FILTER's sequence, the +28 call is made again
        | for the whole list, and the epilogue is re-emitted. a4 the view, a5
        | the MenuItem constructor, a2 the std::function destructor, d2..d5
        | the four functions' slots, d7 the cursor: all callee-saved across
        | the call. d6 and fp are free: the epilogue restores them.
        | ------------------------------------------------------------------
        .align  2
ain_menu:
        lea     12(%sp),%sp                       | the +28 call's arguments
        move.l  (%a4),%a0
        move.l  8(%a0),%fp                        | append
        clr.l   76(%sp)
        pea     0x1
        jsr     mem_new
        clr.l   96(%sp)
        clr.l   112(%sp)
        move.l  %d0,72(%sp)
        move.l  #ain_label,%d0
        move.l  %d0,84(%sp)
        move.l  #MGR_LABEL,%d0
        move.l  %d0,80(%sp)
        pea     0x1
        jsr     mem_new
        clr.l   132(%sp)
        move.l  %d0,108(%sp)
        move.l  #ain_draw,%d0
        move.l  %d0,120(%sp)
        move.l  #MGR_DRAW,%d0
        move.l  %d0,116(%sp)
        lea     32(%sp),%sp
        pea     0x1
        move.l  %a4,%d0                           | the view, stored in place
        move.l  %d0,96(%sp)
        move.l  #ain_change,%d0
        move.l  %d0,108(%sp)
        move.l  #ain_mgr,%d0
        move.l  %d0,104(%sp)
        pea     0x54
        jsr     mem_new
        pea     0x8
        pea     -1
        move.l  %d5,-(%sp)
        move.l  %d4,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %d2,-(%sp)
        move.l  %d0,-(%sp)
        move.l  %d0,%d6
        jsr     (%a5)
        lea     32(%sp),%sp
        move.l  %d6,(%sp)
        move.l  %a4,-(%sp)
        jsr     (%fp)
        move.l  %d5,-(%sp)
        jsr     (%a2)
        move.l  %d4,-(%sp)
        jsr     (%a2)
        move.l  %d3,-(%sp)
        jsr     (%a2)
        move.l  %d2,-(%sp)
        jsr     (%a2)
        move.l  (%a4),%a0
        pea     0x2
        move.l  %d7,-(%sp)
        move.l  %a4,-(%sp)
        move.l  28(%a0),%a0
        jsr     (%a0)                             | the cursor, over the whole list
        movem.l 36(%sp),%d2-%d7/%a2-%fp           | displaced
        lea     144(%sp),%sp
        rts

        | ain_label(a0 = the std::string to construct) -> d0 = a0.
        .align  2
ain_label:
        link.w  %fp,#-4
        move.l  %d2,-(%sp)
        pea     -1(%fp)
        pea     txt_ain
        move.l  %a0,%d2
        move.l  %a0,-(%sp)
        jsr     std_string_from_cstr
        lea     12(%sp),%sp
        move.l  %d2,%d0
        move.l  -8(%fp),%d2
        unlk    %fp
        rts

        | ------------------------------------------------------------------
        | The item's changer and its manager, in cave11's free tail (.aic):
        | neither cave24's tail nor cave19 has room for them.
        | ------------------------------------------------------------------
        .section .aic,"ax"

        | ain_change(functor, -, delta): up one mode or down one, held at
        | the ends, then the view the functor holds is invalidated.
        .align  2
ain_change:
        move.l  12(%sp),%d0
        beq.s   9f
        move.l  %d0,-(%sp)
        jsr     cfg_mode
        move.l  %d0,%d1
        move.l  (%sp)+,%d0
        bmi.s   1f
        addq.l  #1,%d1
        moveq   #MODES - 1,%d0
        cmp.l   %d0,%d1
        bls.s   2f
        move.l  %d0,%d1
        bra.s   2f
1:      subq.l  #1,%d1
        bpl.s   2f
        moveq   #0,%d1
2:      jsr     cfg_set
        move.l  4(%sp),%a0
        move.l  (%a0),%a0                         | the view
        pea     56(%a0)
        jsr     VIEW_INVALIDATE
        addq.l  #4,%sp
9:      rts

        .text                                     | (cave19 has room for this one)

        | ain_mgr(dest, source, op): the changer's std::function manager, for
        | a functor stored in place - the view pointer - as 0019's dfm_mgr.
        .align  2
ain_mgr:
        move.l  4(%sp),%a0                        | dest
        move.l  12(%sp),%d0                       | op
        bne.s   1f
        move.l  #ain_mgr,(%a0)
        bra.s   9f
1:      subq.l  #1,%d0
        bne.s   2f
        move.l  8(%sp),(%a0)
        bra.s   9f
2:      subq.l  #1,%d0
        bne.s   9f
        move.l  8(%sp),%a1
        move.l  (%a1),(%a0)
9:      moveq   #0,%d0
        rts
