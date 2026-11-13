        | Mod 0025 - PERF pads push their track's sound.
        |
        | In PERF mode, a plain pad press (no FUNC, not a repeat) edits the sound
        | of the pad's track (pad 1 = T1 .. pad 12 = T12), each press the same
        | fixed recipe, as knob turns would:
        |   FILTER FRQ   -5% (6.4 knob steps)    FILTER RES   +5%
        |   AMP DEL send +5%                     AMP REV send +5%
        |   LFO: SPD 1..16, MUL in its first quarter (the six slowest), WAV
        |   any, MOD FRE or TRG, SPH 0..31, FAD 0..16, DEP +1..32, DST one of
        |   0004's sixteen destinations, all at random.
        | The edits are ordinary parameter writes: they show on the pages, are
        | saved with the kit, and a kit reload undoes them. FUNC + pad still opens
        | stock's PERF edit view. The pads are lit orange in PERF.
        |
        | perf_keys    detour 0x400ce112, PerformanceView's key handler entry
        | perf_leds    PerformanceView's vtable slot 5 (0x401e2428), the LED pass

        .include "symbols.inc"

        .equ    KEY_RESUME,     0x400ce11a        | past the re-emitted prologue
        .equ    PERF_LEDS,      0x400ce23e        | stock's slot 5
        .equ    PAD_RGB,        0x400a0624        | (LedManager *, pad, r, g, b, blink)
        .equ    PAD0,           0x90              | key code of pad 1
        .equ    PADS,           12
        .equ    EV_CODE,        12                | KeyEvent: key code
        .equ    EV_FLAGS,       16                | bit 0 pressed, 1 FUNC, 3 repeat
        .equ    REGION_PADS,    2
        .equ    PROJ_KIT,       352               | the active kit, as 0000-shared's
        .equ    DTCN0,          0xfc07000c        | DMA timer 0, to stir the draw

        .equ    ID_FRQ,         47
        .equ    ID_RES,         48
        .equ    ID_DEL,         60
        .equ    ID_REV,         61
        .equ    ID_SPD,         64
        .equ    ID_MUL,         65
        .equ    ID_FAD,         66
        .equ    ID_DST,         67
        .equ    ID_WAV,         68
        .equ    ID_SPH,         69
        .equ    ID_MOD,         70
        .equ    ID_DEP,         71

        .equ    STEP,           256               | one knob step, 8.8
        .equ    FIVE_PCT,       1638              | 6.4 steps: 5% of 128
        .equ    SLAM,           -128*STEP         | past any knob's left end

        .equ    ORANGE_R,       15
        .equ    ORANGE_G,       5
        .equ    ORANGE_B,       0

        .text

        | ------------------------------------------------------------------
        | perf_keys: over `linkw %fp,#-28` and the first half of `moveml
        | %d2-%d4/%a2-%a3,%sp@`, both re-emitted. fp@(8) the view, fp@(12) the
        | event. Stock loads d2, a2 and a3 next and sets d3, d4 before reading
        | them, so d0-d4/a0-a3 are free here.
        | ------------------------------------------------------------------
        .align  2
perf_keys:
        link    %fp,#-28                          | displaced
        movem.l %d2-%d4/%a2-%a3,(%sp)             | displaced
        move.l  12(%fp),%a0
        move.l  EV_CODE(%a0),%d0
        sub.l   #PAD0,%d0
        moveq   #PADS-1,%d1
        cmp.l   %d1,%d0
        bhi.s   9f                                | not a pad
        move.l  EV_FLAGS(%a0),%d1
        moveq   #0xb,%d2
        and.l   %d2,%d1
        moveq   #1,%d2
        cmp.l   %d2,%d1
        bne.s   9f                                | a release, FUNC, or a repeat
        move.l  %d0,-(%sp)
        bsr.w   perf_push
        addq.l  #4,%sp
9:      jmp     KEY_RESUME

        | ------------------------------------------------------------------
        | perf_leds(view, regions *): with the pads' region bit set, every pad
        | orange and the bit cleared, so stock's pass leaves them alone; then
        | stock's pass, with the same arguments.
        | ------------------------------------------------------------------
        .align  2
perf_leds:
        move.l  8(%sp),%a0
        moveq   #REGION_PADS,%d0
        and.l   (%a0),%d0
        beq.s   9f
        lea     -12(%sp),%sp
        movem.l %d2-%d3/%a2,(%sp)
        jsr     led_manager
        move.l  %d0,%a2
        moveq   #0,%d2                            | pad
1:      clr.l   -(%sp)                            | no blink
        pea     ORANGE_B
        pea     ORANGE_G
        pea     ORANGE_R
        move.l  %d2,-(%sp)
        move.l  %a2,-(%sp)
        jsr     PAD_RGB
        lea     24(%sp),%sp
        addq.l  #1,%d2
        moveq   #PADS,%d0
        cmp.l   %d0,%d2
        blt.s   1b
        movem.l (%sp),%d2-%d3/%a2
        lea     12(%sp),%sp
        move.l  8(%sp),%a0
        moveq   #~REGION_PADS,%d0
        and.l   %d0,(%a0)
9:      jmp     PERF_LEDS

        | ------------------------------------------------------------------
        | perf_push(track): the recipe on the track's sound set. Keeps d2-d7,
        | a2-a6.
        | ------------------------------------------------------------------
        .align  2
perf_push:
        lea     -16(%sp),%sp
        movem.l %d2-%d4/%a2,(%sp)
        move.l  20(%sp),%d2                       | the track
        jsr     project_singleton
        add.l   #PROJ_KIT,%d0
        move.l  %d2,-(%sp)
        move.l  %d0,-(%sp)
        jsr     kit_param_set
        addq.l  #8,%sp
        move.l  %d0,%a2                           | the track's SoundParameterSet
        tst.l   %d0
        beq.w   9f
        move.l  DTCN0,%d0                         | stir the draw
        eor.l   %d0,pp_seed

        move.l  #-FIVE_PCT,%d1
        moveq   #ID_FRQ,%d0
        bsr.w   turn
        move.l  #FIVE_PCT,%d1
        moveq   #ID_RES,%d0
        bsr.w   turn
        move.l  #FIVE_PCT,%d1
        moveq   #ID_DEL,%d0
        bsr.w   turn
        move.l  #FIVE_PCT,%d1
        moveq   #ID_REV,%d0
        bsr.w   turn

        | The LFO: each knob fully left, then right by its draw. A bipolar
        | knob's 64 steps up to its centre come first.
        lea     lfo_recipe,%a0
1:      move.l  (%a0)+,%d3                        | the id, or 0 at the end
        beq.s   2f
        move.l  (%a0)+,%d4                        | steps to the range's start
        move.l  (%a0)+,%d1                        | how many values the draw has
        move.l  %a0,-(%sp)
        bsr.w   draw                              | d0 = 0..d1-1
        add.l   %d4,%d0
        move.l  %d0,%d4                           | steps from the left end
        move.l  #SLAM,%d1
        move.l  %d3,%d0
        bsr.w   turn
        move.l  %d4,%d1
        moveq   #8,%d0
        lsl.l   %d0,%d1                           | in 8.8
        move.l  %d3,%d0
        bsr.w   turn
        move.l  (%sp)+,%a0
        bra.s   1b

2:      moveq   #16,%d1                           | DST: one of the sixteen
        bsr.w   draw
        lea     dst_indices,%a0
        mvz.b   (%a0,%d0.l),%d0
        moveq   #8,%d1
        lsl.l   %d1,%d0                           | its container index, 8.8
        pea     1
        pea     1
        move.l  %d2,-(%sp)                        | track
        move.l  %d0,-(%sp)                        | value
        pea     ID_DST
        move.l  %a2,-(%sp)                        | set
        jsr     param_set_value
        lea     24(%sp),%sp
9:      movem.l (%sp),%d2-%d4/%a2
        lea     16(%sp),%sp
        rts

        | turn(d0 = id, d1 = delta 8.8; a2 = the set, d2 = the track): a knob
        | turn through the set's own delta handler, so ranges and the display
        | are stock's. Keeps d2-d4/a2.
turn:
        clr.l   -(%sp)                            | outFlag: none
        clr.l   -(%sp)                            | funcHeld: no
        move.l  %d2,-(%sp)                        | track
        move.l  %d1,-(%sp)                        | delta
        move.l  %d0,-(%sp)                        | id
        move.l  %a2,-(%sp)                        | set
        jsr     param_set_apply_delta
        lea     24(%sp),%sp
        rts

        | draw(d1 = n) -> d0 = 0..n-1. A 32-bit LCG, the high half scaled.
        | Uses d0, d1.
draw:
        move.l  %d1,-(%sp)
        move.l  pp_seed,%d0
        move.l  #1103515245,%d1
        mulu.l  %d1,%d0
        add.l   #12345,%d0
        move.l  %d0,pp_seed
        swap    %d0
        and.l   #0xffff,%d0
        move.l  (%sp)+,%d1
        mulu.l  %d1,%d0
        swap    %d0
        and.l   #0xffff,%d0
        rts

        | The tables and the seed, in .pdata (cave22).
        .section .pdata,"aw"

        | {id, steps from the left end to the range's start, values}: the LFO
        | knobs in the first quarter of their range, near 0. SPD, FAD and DEP
        | are bipolar (-64..63), so their range starts 64 steps in.
        .align  2
lfo_recipe:
        .long   ID_SPD, 64 + 1, 16                | SPD 1..16
        .long   ID_MUL, 0, 6                      | MUL the six slowest
        .long   ID_FAD, 64, 17                    | FAD 0..16
        .long   ID_WAV, 0, 7                      | WAV any of the seven
        .long   ID_SPH, 0, 32                     | SPH 0..31
        .long   ID_MOD, 0, 2                      | MOD FRE or TRG
        .long   ID_DEP, 64 + 1, 32                | DEP 1..32
        .long   0

        | 0004's sixteen: the 8 machine parameters, sample FIN and STA, filter
        | FRQ and RES, amp DEC and PAN, the DEL and REV sends.
dst_indices:
        .byte   9, 10, 11, 12, 13, 14, 15, 16
        .byte   18, 21, 30, 31, 35, 38, 40, 41

        .align  2
pp_seed: .long  0x2545f491
