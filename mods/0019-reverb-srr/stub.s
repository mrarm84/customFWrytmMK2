        | Mod 0019 - a phaser on the REVERB page, a REVERB 2 page of crusher,
        | chorus, comb, ring and hiss, and a filter on the DISTORTION page.
        |
        | THE PHS PARAMETER. The FX track's sound is the engine's track 12: 42
        | words, live at kit +0x74a, uploaded by the same per-track path as the
        | voices' (0x4011f686 -> 0x4011da62, all 0x54 bytes), so word k lands
        | in the engine's working array at 0x8000fb98 + 2k with locks and LFO
        | applied. Stock's FX parameters use k = 9..37 - TIME is 9 at
        | 0x8000fbaa, the reverb's PRE..VOL 19..25, the compressor 30..37 from
        | 0x8000fbd4 - all but k = 29, 0x8000fbd2, which no record names. The
        | kit's FX save and load (0x40007f58, 0x40007f02) carry word 29 anyway,
        | to stored slot 20 and back. Record 460 (CB_VCA, the hidden CB TEST
        | machine's) is given the reverb records' shape for it and goes in the
        | REVERB page's empty encoder G (hardware-verified 2026-11-11, as SRR).
        | It is now PHS, the phaser's rate (ph_go below); its press steps the
        | phaser OFF (PH-), on the reverb's output (PHS), on the delay's input
        | (PHS.), cfg byte 8.
        |
        | REVERB 2 (page 14) is WID, SRR, HIS, 12B, DRK, SAT, TRM, RNG (lite);
        | see cave31 below for all but SRR.
        |
        | SRR N holds each sample for N + 1 samples: 0 is off and bit-exact
        | stock, 1 is 24 kHz, 127 is 375 Hz. The hold count carries across
        | blocks. It is REVERB 2's B (rv2_val), and BIT goes where it goes.
        |
        | WHERE THE SRR SITS. srr_mode, kept in the persisted gap (cfg below):
        |   0 REV  the reverb's output, after the render (fx_post): only what
        |          is heard is crushed, the reverb's tail is never fed back
        |          crushed. The label reads "SRR".
        |   1 DLY  the delay's input, after the sends are built and before the
        |          delay renders (dly_pre, 0x4010e740): the delay line holds the
        |          crushed send, so every repeat - and the delay's send into the
        |          reverb - is crushed, and the reverb's own output is not. The
        |          label reads "SRR." - the dot marks the mode.
        | A press on SRR toggles it.
        |
        | MOMENTARY. FUNC + holding SRR down crushes the whole output: the PRE
        | and POST pairs of the output ring (channels 12..15), after the voices
        | (0013's DAC SUM) and both returns are in them, at the knob's SRR, or
        | MOM_N when that is 0. The label reads "ALL" (or "ALL.") while held.
        | With DAC SUM off the voices are on the analog bus and only the
        | returns are crushed. Set by the key handler on the press, cleared on
        | the release, and in the interrupt whenever the key is not held, so a
        | release on another page cannot leave it on.
        |
        | THE DIST FILTER. The DISTORTION page's empty encoders D, E and F are
        | FRQ, RES and TYP: a biquad over the PRE pair of the output ring, the
        | digital signal that enters the analog mix ahead of the master
        | distortion and compressor - with 0013's DAC SUM on, every voice and
        | the PRE returns. The distortion and compressor are analog
        | (re/subsystems/audio-engine.md), so a filter after them is not
        | possible; this one shapes what the distortion is fed. TYP is OFF,
        | LP2, BP, HP2 or BS, shown as stock's FILTER TYP names; FRQ is stock's
        | FRQ scale (a semitone a step, 440 Hz at 60), RES the Q (0.707..2.0
        | for LP2 and HP2, 0.5..8 for BP and BS). The section is 0013's,
        | hardware-verified there: the RBJ cookbook's, Q30 coefficients, the
        | same cos/sin and 1/(2Q) tables (copied verbatim), direct form I
        | summed at half scale and doubled with saturation. Coefficients are
        | worked out again only when TYP, FRQ or RES change.
        |
        | They are FX words 38, 39 and 40 (TYP, FRQ, RES), which the engine
        | uploads with the other 42 but which stock's kit save and load do not
        | carry: kfx_save writes them, with a tag, into the stored FX block's
        | unused bytes +0x50..+0x53 (kit +0x816..+0x819, which stock's FX save
        | never writes and its load never reads), kfx_load reads them back,
        | defaults without the tag, and kfx_init opens FRQ in a fresh kit.
        | Records 459, 456 and 458 (CB TEST's CB_8ENV, CY TEST's CY_VCA, CB
        | TEST's CB_5ENV - hidden machines', never shown by stock) carry them,
        | so the knobs, popups, p-locks and LFO are stock's.
        |
        | DIST FILTER in SETTINGS > AUDIO ROUTING, after 0013's DAC SUM, turns
        | the filter off device-wide (ON by default).
        |
        | STORAGE (cfg). Device-wide, in the persisted gap at 0x405c8e90
        | (re/subsystems/control-inputs.md): tag "DSTF", a version byte, DIST
        | FILTER, srr_mode, the chorus's and the phaser's modes. A bad tag
        | reads as ON, REV, OFF and OFF; the first change
        | writes a fresh record, the settings first and the tag last.

        .include "symbols.inc"

        .equ    PHS_WORD,       0x8000fbd2        | FX word 29, 8.8: the phaser's rate
        .equ    DF_TYP_W,       0x8000fbe4        | FX word 38
        .equ    DF_FRQ_W,       0x8000fbe6        | FX word 39
        .equ    DF_RES_W,       0x8000fbe8        | FX word 40
        .equ    LW_BITS,        82                | FX word 41, unused (was BIT)
        .equ    REVERB_OUT,     0x80007b44
        .equ    DELAY_SEND,     0x80007a44
        .equ    FRAMES,         32
        .equ    VMAX,           127
        .equ    MOM_N,          11                | 4 kHz when the knob is at 0

        .equ    OUT_RING,       0x80000000        | four slots of 32 frames, 2048 B
        .equ    OUT_IDX,        0x42f92124
        .equ    OUT_PRE,        48                | channels 12, 13
        .equ    OUT_POST,       56                | channels 14, 15
        .equ    OUT_STRIDE,     64

        .equ    AUDIO_RESUME,   0x401213aa
        .equ    SEND_LOOP,      0x4010e676
        .equ    SEND_DONE,      0x4010e74a
        .equ    KEY_RESUME,     0x4003a5dc
        .equ    KLOAD_RESUME,   0x40007f42
        .equ    KSAVE_RESUME,   0x40007fa8
        .equ    KINIT_RESUME,   0x400117ca
        .equ    TEXT_RESUME,    0x400a8650
        .equ    VIEW_INVALIDATE, 0x40078514

        .equ    KEY_FUNC,       0x80
        .equ    KEY_ENC_G,      0x76              | encoder G's push, 0x70 + 6
        .equ    KNOB_G,         6
        .equ    VT_KNOB_ID,     156               | ParameterPageView: knob -> id

        .equ    ID_PHS,         460               | REVERB G, FX word 29: the phaser
        .equ    ID_CHR,         336               | REVERB 2 D, the chorus rate
        .equ    ID_SRR,         334               | REVERB 2 B, in rv2_val
        .equ    ID_DEP,         337               | REVERB 2 E, the chorus depth
        .equ    ID_DTYP,        458
        .equ    ID_STOCK_TYP,   49
        .equ    PARAM_INFO,     0x419a4888        | RAM records, 0x54 B an id
        .equ    PI_STRIDE,      0x54

        .equ    T_LP2,          1
        .equ    T_BP,           2
        .equ    T_HP2,          3
        .equ    T_BS,           4
        .equ    T_MAX,          4

        .equ    KTAG,           0xd5              | stored FX block +0x50
        .equ    KOFF,           0x50
        .equ    LW_TYP,         76                | live FX words 38..40
        .equ    LW_FRQ,         78
        .equ    LW_RES,         80

        .equ    CFG,            0x405c8e90
        .equ    CFG_TAG,        0x44535446        | "DSTF"
        .equ    CFG_VER,        1
        .equ    CFG_DIST,       5
        .equ    CFG_MODE,       6
        .equ    CFG_CHO,        7                 | the chorus: 0 off, 1 reverb, 2 delay
        .equ    CFG_PHS,        8                 | the phaser, the same
        .equ    CFG_R2R,        9                 | REVERB 2's route: a set bit is on the delay

        .equ    TXT_SRR,        0x53525200        | "SRR"
        .equ    TXT_ALL,        0x414c4c00        | "ALL"
        .equ    DOT,            0x2e

        | AudioRoutingMenuView's item list, 0x400d8cb6, after 0013's DAC SUM.
        .equ    MGR_LABEL,      0x400d8aca
        .equ    MGR_DRAW,       0x400d8b1c
        .equ    MENU_RESUME,    0x400d902a        | the jsr of the view's vtable +28
        .equ    TEXT_WIDTH,     0x40071b86        | (font, -1, std::string *) -> px
        .equ    MENU_FONT,      0x4027a6c8

        .text

        | ------------------------------------------------------------------
        | fx_post: the audio interrupt just after the effects render, over
        | `addql #4,%sp; clrl %d1` and the first half of `lea 0x8000e508,%a1`,
        | all three re-emitted. Everything is saved; MACSR goes to 0xa0
        | (fractional, saturating, as stock's PRE consumer sets it) for the
        | filter and back to its resting value after, and the accumulators are
        | cleared first and left clear, as stock's loops leave them.
        | ------------------------------------------------------------------
        .align  2
fx_post:
        lea     -64(%sp),%sp
        movem.l %d0-%d7/%a0-%a6,(%sp)
        move.l  %macsr,%d0
        move.l  %d0,60(%sp)
        move.l  #0xa0,%macsr
        moveq   #0,%d0
        move.l  %d0,%acc0
        move.l  %d0,%acc2

        bsr.w   df_knobs
        jsr     rv2_knobs
        move.l  OUT_IDX,%d0
        moveq   #11,%d1
        lsl.l   %d1,%d0
        add.l   #OUT_RING,%d0
        move.l  %d0,%a6                           | this block's ring slot
        bsr.w   df_run

        bsr.w   srr_amount                        | d2 = SRR, 0..127
        bsr.w   cfg_mode
        bne.s   1f
        lea     REVERB_OUT,%a1                    | REV: the reverb's output
        lea     srr_rev,%a2
        moveq   #8,%d7
        bsr.w   srr_go
        bra.s   2f
1:      clr.l   srr_rev
2:      bsr.w   cfg_phs                           | the phaser, on the reverb
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bne.s   6f
        lea     REVERB_OUT,%a1
        jsr     ph_go
6:      jsr     cfg_r2r                           | REVERB 2's effects: those
        not.l   %d0                               | not on the delay
        move.l  %d0,rv2_mask
        lea     REVERB_OUT,%a1
        jsr     rv2_go
        lea     REVERB_OUT,%a1                    | 12B, last
        jsr     b12_go
        bsr.w   srr_amount
        bsr.w   mom_active
        beq.s   3f
        tst.l   %d2
        bne.s   4f
        moveq   #MOM_N,%d2
4:      lea     OUT_PRE(%a6),%a1
        lea     srr_mpre,%a2
        moveq   #OUT_STRIDE,%d7
        bsr.w   srr_go
        lea     OUT_POST(%a6),%a1
        lea     srr_mpost,%a2
        bsr.w   srr_go
        bra.s   5f
3:      clr.l   srr_mpre
        clr.l   srr_mpost
5:      jsr     pnc_go                            | PANIC's fade, after everything
        bsr.w   srr_label
        jsr     cho_label
        jsr     r2_label

        move.l  60(%sp),%d0
        move.l  %d0,%macsr
        movem.l (%sp),%d0-%d7/%a0-%a6
        lea     64(%sp),%sp
        addq.l  #4,%sp                            | displaced
        clr.l   %d1                               | displaced
        lea     0x8000e508,%a1                    | displaced
        jmp     AUDIO_RESUME

        | srr_amount -> d2 = the SRR knob, 0..127. Uses d0.
        .align  2
srr_amount:
        mvz.w   rv2_val,%d2                       | REVERB 2's SRR
        lsr.l   #8,%d2
        bpl.s   1f
        moveq   #0,%d2
1:      moveq   #VMAX,%d0
        cmp.l   %d0,%d2
        ble.s   2f
        move.l  %d0,%d2
2:      rts

        | srr_go(d2 = N, a1 = the first left word, d7 = the frame stride,
        | a2 = state {count, held L, held R}): the sample-and-hold over 32
        | stereo frames, in place; N = 0 clears the count, so the next on
        | loads at once. Uses d3..d6, a1.
        .align  2
srr_go:
        tst.l   %d2
        bne.s   1f
        clr.l   (%a2)
        rts
1:      movem.l (%a2),%d3-%d5
        moveq   #FRAMES-1,%d6
2:      subq.l  #1,%d3
        bpl.s   3f
        move.l  (%a1),%d4                         | a new sample
        move.l  4(%a1),%d5
        move.l  %d2,%d3                           | held for N more
3:      move.l  %d4,(%a1)
        move.l  %d5,4(%a1)
        add.l   %d7,%a1
        subq.l  #1,%d6
        bpl.s   2b
        movem.l %d3-%d5,(%a2)
        rts

        | mom_active -> Z clear when the momentary SRR is on: mom_on set by a
        | press and encoder G still held; cleared here otherwise. is_key_held
        | only reads the key table. Keeps d2..d7, a2..a6.
        .align  2
mom_active:
        tst.b   mom_on
        beq.s   9f
        mvz.b   mom_key,%d0
        move.l  %d0,-(%sp)
        jsr     is_key_held
        addq.l  #4,%sp
        tst.l   %d0
        bne.s   9f
        clr.b   mom_on
9:      tst.b   mom_on
        rts

        | srr_label: the record's short name, "SRR" or "ALL" while the
        | momentary is on, with a trailing dot in DLY mode. The page reads it
        | through the record at every draw (0x400a8f94). Uses d0, d1, a0.
        .align  2
srr_label:
        move.l  #TXT_SRR,%d1
        tst.b   mom_on
        beq.s   1f
        move.l  #TXT_ALL,%d1
1:      bsr.w   cfg_mode
        beq.s   2f
        moveq   #DOT,%d0
        or.l    %d0,%d1
2:      lea     txt_srr_short,%a0
        move.l  %d1,(%a0)
        clr.b   4(%a0)
        rts

        | ------------------------------------------------------------------
        | df_knobs: DIST TYP's encoder takes stock FILTER TYP's range start
        | and acceleration, with T_MAX as its top, as 0013's flt_knobs does
        | for its own TYP - without it the knob runs to 127. Idempotent, a few
        | words a block. Uses a0, a1, d0.
        | ------------------------------------------------------------------
        .align  2
df_knobs:
        lea     PARAM_INFO+ID_STOCK_TYP*PI_STRIDE,%a0
        lea     PARAM_INFO+ID_DTYP*PI_STRIDE,%a1
        move.l  4(%a0),4(%a1)
        move.l  #T_MAX << 8,%d0
        move.l  %d0,8(%a1)
        move.l  16(%a0),16(%a1)
        rts

        | ------------------------------------------------------------------
        | df_run(a6 = the ring slot): the DIST filter over the PRE pair, in
        | place. Off (DIST FILTER OFF, or TYP OFF) keeps each side's state on
        | the signal - every term its last sample - so turning it on starts
        | from there, as 0013's slots do. Clobbers d0..d7, a0..a5.
        | ------------------------------------------------------------------
        .align  2
df_run:
        bsr.w   cfg_dist
        beq.w   8f
        mvs.w   DF_TYP_W,%d4
        asr.l   #8,%d4
        ble.w   8f
        moveq   #T_MAX,%d0
        cmp.l   %d0,%d4
        bgt.w   8f
        mvs.w   DF_RES_W,%d3
        bsr.w   df_clamp
        move.l  %d3,%d1                           | RES, 0..127
        mvs.w   DF_FRQ_W,%d3
        bsr.w   df_clamp                          | FRQ, 0..127
        move.l  %d4,%d0
        swap    %d0
        move.l  %d3,%d2
        lsl.l   #8,%d2
        or.l    %d2,%d0
        or.l    %d1,%d0                           | TYP << 16, FRQ << 8, RES
        cmp.l   df_key,%d0
        beq.s   1f
        move.l  %d0,df_key
        bsr.w   df_coef
1:      lea     df_coefs,%a1
        lea     OUT_PRE(%a6),%a2
        lea     df_state,%a0
        bsr.s   df_chan
        lea     df_coefs,%a1
        lea     OUT_PRE+4(%a6),%a2
        lea     df_state+16,%a0
        bsr.s   df_chan
        rts
8:      moveq   #-1,%d0
        move.l  %d0,df_key
        lea     df_state,%a0
        move.l  OUT_PRE+(FRAMES-1)*OUT_STRIDE(%a6),%d0
        lsl.l   #8,%d0
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        move.l  OUT_PRE+4+(FRAMES-1)*OUT_STRIDE(%a6),%d0
        lsl.l   #8,%d0
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        rts

        | df_clamp(d3 = an 8.8 word, sign-extended) -> d3 = 0..127. Uses d0.
        .align  2
df_clamp:
        asr.l   #8,%d3
        bpl.s   1f
        moveq   #0,%d3
1:      moveq   #VMAX,%d0
        cmp.l   %d0,%d3
        ble.s   2f
        move.l  %d0,%d3
2:      rts

        | df_chan(a1 = coefficients, a2 = the side's first word, a0 = its
        | state {x1, x2, y1, y2}): direct form I, as 0013's bq_run,
        |   y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2
        | five multiplies a frame at half scale, doubled with saturation. The
        | ring holds Q31 >> 8 (logical), so x is the word << 8 and y goes back
        | >> 8. Clobbers d0..d7, a2..a5.
        .align  2
df_chan:
        movem.l (%a1),%d5-%d7/%a3-%a4             | b0, b1, b2, -a1, -a2
        movem.l (%a0),%d1-%d4                     | x1, x2, y1, y2
        lea     FRAMES*OUT_STRIDE(%a2),%a5
1:      move.l  (%a2),%d0
        lsl.l   #8,%d0                            | x, Q31
        mac.l   %d0,%d5,%acc0
        mac.l   %d1,%d6,%acc0
        mac.l   %d2,%d7,%acc0
        mac.l   %d3,%a3,%acc0
        mac.l   %d4,%a4,%acc0
        move.l  %d1,%d2                           | x2 = x1
        move.l  %d0,%d1                           | x1 = x
        move.l  %d3,%d4                           | y2 = y1
        movclr.l %acc0,%d3                        | y / 2
        add.l   %d3,%d3
        sats.l  %d3                               | y1 = y, saturated
        move.l  %d3,%d0
        lsr.l   #8,%d0
        move.l  %d0,(%a2)
        lea     OUT_STRIDE(%a2),%a2
        cmpa.l  %a5,%a2
        bne.s   1b
        movem.l %d1-%d4,(%a0)
        rts

        | df_coef(d4 = TYP, d3 = FRQ, d1 = RES): (b0, b1, b2, -a1, -a2) into
        | df_coefs, Q30 - 0013's bq_coef with the dry/wet mix left out (its
        | FULL depth), on the same tables. alpha = sin(w0) kq, kq = 1 / (2 Q)
        | by RES; a0 = 1 + alpha, whose reciprocal is a 16-bit estimate from
        | divu.l and one Newton step. Each product with a Q30 operand is
        | doubled after its movclr. Clobbers d0..d7, a0.
        .align  2
df_coef:
        lea     df_cos,%a0
        move.l  (%a0,%d3.l*4),%d6                 | c, Q31
        lea     df_sin,%a0
        move.l  (%a0,%d3.l*4),%d2                 | s, Q31
        lea     df_kq_lh,%a0
        cmp.l   #T_LP2,%d4
        beq.s   1f
        cmp.l   #T_HP2,%d4
        beq.s   1f
        lea     df_kq_bp,%a0
1:      mvz.w   (%a0,%d1.l*2),%d0
        swap    %d0                               | kq, Q31
        mac.l   %d2,%d0,%acc2
        movclr.l %acc2,%d5                        | alpha, Q31
        move.l  %d5,%d2
        asr.l   #1,%d2
        add.l   #0x40000000,%d2                   | a0, Q30
        move.l  %d2,%d3
        moveq   #15,%d0
        lsr.l   %d0,%d3
        move.l  #0x7fffffff,%d0
        divu.l  %d3,%d0
        moveq   #14,%d3
        lsl.l   %d3,%d0                           | 1 / a0, about 16 bits
        mac.l   %d2,%d0,%acc2
        movclr.l %acc2,%d3                        | a0 inv
        add.l   %d3,%d3
        move.l  #0x40000000,%d1
        sub.l   %d3,%d1                           | 1 - a0 inv
        mac.l   %d0,%d1,%acc2
        movclr.l %acc2,%d3
        add.l   %d3,%d3
        add.l   %d3,%d0                           | inv, Q30
        lea     df_coefs,%a0
        mac.l   %d6,%d0,%acc2
        movclr.l %acc2,%d3
        add.l   %d3,%d3
        move.l  %d3,12(%a0)                       | -a1 = 2 c / a0
        move.l  #0x40000000,%d1
        move.l  %d5,%d3
        asr.l   #1,%d3
        sub.l   %d3,%d1                           | 1 - alpha, Q30
        mac.l   %d1,%d0,%acc2
        movclr.l %acc2,%d3
        add.l   %d3,%d3
        neg.l   %d3
        move.l  %d3,16(%a0)                       | -a2 = -(1 - alpha) / a0
        cmp.l   #T_LP2,%d4
        bne.s   2f
        move.l  #0x40000000,%d1
        asr.l   #1,%d6
        sub.l   %d6,%d1                           | 1 - c, Q30
        mac.l   %d1,%d0,%acc2
        movclr.l %acc2,%d2                        | b1 = (1 - c) / a0
        add.l   %d2,%d2
        move.l  %d2,%d1
        asr.l   #1,%d1                            | b0
        move.l  %d1,%d3                           | b2
        bra.s   6f
2:      cmp.l   #T_HP2,%d4
        bne.s   3f
        move.l  #0x40000000,%d1
        asr.l   #1,%d6
        add.l   %d6,%d1                           | 1 + c, Q30
        mac.l   %d1,%d0,%acc2
        movclr.l %acc2,%d2
        add.l   %d2,%d2
        move.l  %d2,%d1
        asr.l   #1,%d1                            | b0 = (1 + c) / 2 a0
        move.l  %d1,%d3                           | b2
        neg.l   %d2                               | b1
        bra.s   6f
3:      cmp.l   #T_BS,%d4
        bne.s   4f
        move.l  %d0,%d1                           | b0 = 1 / a0
        move.l  %d0,%d3                           | b2
        move.l  12(%a0),%d2
        neg.l   %d2                               | b1 = -2 c / a0
        bra.s   6f
4:      asr.l   #1,%d5                            | BP: alpha, Q30
        mac.l   %d5,%d0,%acc2
        movclr.l %acc2,%d1                        | b0 = alpha / a0
        add.l   %d1,%d1
        moveq   #0,%d2
        move.l  %d1,%d3
        neg.l   %d3                               | b2
6:      move.l  %d1,(%a0)
        move.l  %d2,4(%a0)
        move.l  %d3,8(%a0)
        rts

        | ------------------------------------------------------------------
        | dly_pre: the sends loop's end in 0x4010e650, over `moveq #2,%d0;
        | addql #1,%d3; cmpl %d3,%d0`, re-emitted, the stub then taking the
        | `bnew 0x4010e676` after them. When both sends are built (d3 = 2) and
        | the SRR is in DLY mode, the delay's send is crushed before the delay
        | renders it (jsr 0x4010d9b8 at 0x4010e758). Everything it touches is
        | saved; no MAC.
        | ------------------------------------------------------------------
        .align  2
dly_pre:
        moveq   #2,%d0                            | displaced
        addq.l  #1,%d3                            | displaced
        cmp.l   %d3,%d0                           | displaced
        beq.s   1f
        jmp     SEND_LOOP
1:      lea     -56(%sp),%sp
        movem.l %d0-%d7/%a0-%a5,(%sp)
        bsr.w   cfg_mode
        beq.s   8f
        bsr.w   srr_amount
        lea     DELAY_SEND,%a1
        lea     srr_dly,%a2
        moveq   #8,%d7
        bsr.w   srr_go
        bra.s   7f
8:      clr.l   srr_dly
7:      bsr.w   cfg_phs                           | the phaser on the delay's input
        moveq   #2,%d1
        cmp.l   %d1,%d0
        bne.s   6f
        lea     DELAY_SEND,%a1
        jsr     ph_go
6:      jsr     cfg_r2r                            | REVERB 2's, those on the delay
        tst.l   %d0
        beq.s   9f
        move.l  %d0,rv2_mask
        lea     DELAY_SEND,%a1
        jsr     rv2_go
9:      lea     DELAY_SEND,%a1                    | 12B, last
        jsr     b12_go
        movem.l (%sp),%d0-%d7/%a0-%a5
        lea     56(%sp),%sp
        jmp     SEND_DONE

        | ------------------------------------------------------------------
        | knob_key: ParameterPageView's key handler, on the encoder-push path
        | (keys 0x70..0x77), over `movel %d2,%sp@-; jsr %a3@; moveal %a2@,%a0`,
        | re-emitted: d0 the key code, a0 the view's vtable, a2 the view, d2
        | the event (+12 the code, +16 the flags: bit 0 down, bit 3 a repeat).
        | PHS (REVERB G) and CHR (REVERB 2 D): a fresh press steps the mode,
        | OFF, REV, DLY. SRR (REVERB 2 B): a fresh press toggles
        | srr_mode (REV/DLY), with FUNC held starts the momentary instead; a
        | release ends it. Stock's own push handling follows unchanged. d0, d1, a0 and a1
        | are given back as the displaced code left them.
        | ------------------------------------------------------------------
        .section .kk,"ax"
        .align  2
        | rv2_knobs: the seven RAM records take record 410's flags, range,
        | acceleration and formatters (a plain 0..127 knob, as 0021's DG knobs
        | have), once after boot, with the range 0..127 set. Uses d0, d1, a0,
        | a1.
rv2_knobs:
        lea     PARAM_INFO+ID_REF*PI_STRIDE,%a0
        lea     PARAM_INFO+(ID_R2+R2N-1)*PI_STRIDE,%a1
        move.l  0x20(%a0),%d0
        cmp.l   0x20(%a1),%d0
        beq.s   3f
        lea     PARAM_INFO+ID_R2*PI_STRIDE,%a1
        moveq   #R2N,%d1
1:      lea     PARAM_INFO+ID_REF*PI_STRIDE,%a0
        moveq   #13,%d0
2:      move.l  (%a0)+,(%a1)+
        subq.l  #1,%d0
        bne.s   2b
        clr.l   4-0x34(%a1)                       | the range: 0..127
        move.l  #VMAX << 8,%d0
        move.l  %d0,8-0x34(%a1)
        lea     PI_STRIDE-0x34(%a1),%a1
        subq.l  #1,%d1
        bne.s   1b
3:      rts

        .align  2
knob_key:
        move.l  %d2,-(%sp)                        | displaced
        jsr     (%a3)                             | displaced
        move.l  (%a2),%a0                         | displaced
        cmp.l   #0x70,%d0
        blt.w   9f
        cmp.l   #0x77,%d0
        bgt.w   9f
        lea     -16(%sp),%sp
        movem.l %d0-%d1/%a0-%a1,(%sp)
        sub.l   #0x70,%d0
        move.l  %d0,-(%sp)                        | the knob
        move.l  %a2,-(%sp)
        move.l  VT_KNOB_ID(%a0),%a0
        jsr     (%a0)
        addq.l  #8,%sp
        move.l  %d0,%d1                           | its id
        move.l  %d2,%a0
        move.l  16(%a0),%d0                       | flags
        cmp.l   #ID_PHS,%d1
        bne.s   51f
        moveq   #CFG_PHS,%d1
        bra.w   52f
51:     cmp.l   #ID_SRR,%d1
        beq.w   5f
        sub.l   #ID_R2,%d1                        | the others: their route bit
        cmp.l   #R2N,%d1
        bcc.w   8f
        lea     r2_rbit,%a0
        mvs.b   (%a0,%d1.l),%d1
        bmi.w   8f
        btst    #0,%d0
        beq.w   8f
        btst    #3,%d0
        bne.w   8f
        movea.l %d1,%a1
        jsr     cfg_r2r
        move.l  %a1,%d1
        bchg    %d1,%d0
        move.l  %d0,%d1
        moveq   #CFG_R2R,%d0
        jsr     cfg_set
        bra.w   4f
52:     btst    #0,%d0                            | a fresh press: the next mode
        beq.w   8f
        btst    #3,%d0
        bne.w   8f
        move.l  %d1,-(%sp)
        move.l  %d1,%d0
        jsr     cfg_get
        addq.l  #1,%d0
        moveq   #3,%d1
        cmp.l   %d1,%d0
        blt.s   6f
        moveq   #0,%d0
6:      move.l  %d0,%d1
        move.l  (%sp)+,%d0
        jsr     cfg_set
        bra.s   4f
5:      btst    #0,%d0
        beq.s   3f                                | the release
        btst    #3,%d0
        bne.w   8f                                | a repeat
        move.l  (%sp),%d0                         | the key, for mom_active
        move.b  %d0,mom_key
        pea     KEY_FUNC
        jsr     is_key_held
        addq.l  #4,%sp
        tst.l   %d0
        bne.s   2f                                | FUNC + hold: the momentary
        jsr     cfg_mode                          | a press: the other route
        seq     %d1
        and.l   #1,%d1
        moveq   #CFG_MODE,%d0
        jsr     cfg_set
        bra.s   4f
2:      moveq   #1,%d0
        move.b  %d0,mom_on
        bra.s   4f
3:      clr.b   mom_on
4:      jsr     srr_label
        jsr     cho_label
        jsr     r2_label
        move.l  %a2,-(%sp)
        jsr     VIEW_INVALIDATE
        addq.l  #4,%sp
8:      movem.l (%sp),%d0-%d1/%a0-%a1
        lea     16(%sp),%sp
9:      jmp     KEY_RESUME
        .text

        | ------------------------------------------------------------------
        | The DIST filter's words in the kit.
        |
        | kfx_load: the kit's FX load (0x40007f02) after its word loop, over
        | `mvsb %a0@(8),%d0; movel %a3@(0,%d0:l:4),%d0`, both re-emitted: a0
        | the live words, a1 the stored block. Tagged: words 38..40 from
        | +0x51..+0x53; else TYP OFF, FRQ 127, RES 0.
        | ------------------------------------------------------------------
        .align  2
kfx_load:
        lea     -12(%sp),%sp
        movem.l %d0-%d2,(%sp)
        mvz.b   KOFF(%a1),%d0
        cmp.l   #KTAG,%d0
        bne.s   2f
        mvz.b   KOFF+1(%a1),%d0                   | OCT: +1 bits 3..7, +2 bit 7, +3 bit 7
        move.l  %d0,%d1
        lsr.l   #3,%d1
        btst    #7,KOFF+2(%a1)
        beq.s   11f
        moveq   #32,%d2
        or.l    %d2,%d1
11:     btst    #7,KOFF+3(%a1)
        beq.s   12f
        moveq   #64,%d2
        or.l    %d2,%d1
12:     lsl.l   #8,%d1
        move.w  %d1,oct_ld
        moveq   #7,%d1
        and.l   %d1,%d0
        moveq   #T_MAX,%d1
        cmp.l   %d1,%d0
        bls.s   1f
        moveq   #0,%d0
1:      lsl.l   #8,%d0
        move.w  %d0,LW_TYP(%a0)
        mvz.b   KOFF+2(%a1),%d0
        and.l   #0x7f,%d0
        lsl.l   #8,%d0
        move.w  %d0,LW_FRQ(%a0)
        mvz.b   KOFF+3(%a1),%d0
        and.l   #0x7f,%d0
        lsl.l   #8,%d0
        move.w  %d0,LW_RES(%a0)
        bra.s   3f
2:      moveq   #0,%d0
        move.w  %d0,LW_TYP(%a0)
        move.w  %d0,oct_ld
        move.w  %d0,LW_RES(%a0)
        move.l  #VMAX << 8,%d0
        move.w  %d0,LW_FRQ(%a0)
3:      move.l  %a0,-(%sp)
        jsr     rv2_load                          | REVERB 2's seven
        movea.l (%sp)+,%a0
        move.w  oct_ld,%d0                        | and OCT, kept in DIST's bytes
        move.w  %d0,rv2_val+V_OCT
        movem.l (%sp),%d0-%d2
        lea     12(%sp),%sp
        mvs.b   8(%a0),%d0                        | displaced
        move.l  (%a3,%d0.l*4),%d0                 | displaced
        jmp     KLOAD_RESUME

        | kfx_save: the kit's FX save (0x40007f58) after its memset, over
        | `clrl %a2@; lea %sp@(12),%sp`, both re-emitted: a2 the stored block,
        | the live words its second argument, at 28(%sp) here (memset's three
        | arguments, a2, a3, the return, the first argument above it). a1 and
        | d0 are the caller's to lose.
        .align  2
kfx_save:
        move.l  28(%sp),%a1
        moveq   #KTAG-256,%d0
        move.b  %d0,KOFF(%a2)
        move.l  %d1,-(%sp)
        move.l  %d2,-(%sp)
        mvz.b   rv2_val+V_OCT,%d2                 | OCT, 0..127
        move.l  %d2,%d0                           | OCT's low 5 bits << 3 + TYP
        moveq   #31,%d1
        and.l   %d1,%d0
        lsl.l   #3,%d0
        mvz.b   LW_TYP(%a1),%d1
        and.l   #7,%d1
        or.l    %d1,%d0
        move.b  %d0,KOFF+1(%a2)
        mvz.b   LW_FRQ(%a1),%d0                   | FRQ, OCT's bit 5 in bit 7
        and.l   #0x7f,%d0
        btst    #5,%d2
        beq.s   1f
        or.l    #0x80,%d0
1:      move.b  %d0,KOFF+2(%a2)
        mvz.b   LW_RES(%a1),%d0                   | RES, OCT's bit 6 in bit 7
        and.l   #0x7f,%d0
        btst    #6,%d2
        beq.s   2f
        or.l    #0x80,%d0
2:      move.b  %d0,KOFF+3(%a2)
        move.l  (%sp)+,%d2
        move.l  (%sp)+,%d1
        jsr     rv2_save                          | REVERB 2's seven
        clr.l   (%a2)                             | displaced
        lea     12(%sp),%sp                       | displaced
        jmp     KSAVE_RESUME

        | kfx_init: the kit's FX defaults (0x40011770) at its end, over
        | `moveml %sp@,%d2/%a2-%a4; lea %sp@(28),%sp`, both re-emitted. a2 is
        | the words' end (base + 84), or 0 when the routine was given none.
        | FRQ starts open; TYP and RES are left as the defaults gave them.
        .align  2
kfx_init:
        move.l  %a2,%d0
        beq.s   1f
        move.l  #VMAX << 8,%d0
        move.w  %d0,LW_FRQ-84(%a2)
        clr.w   LW_BITS-84(%a2)
1:      jsr     rv2_init                          | REVERB 2's seven
        movem.l (%sp),%d2/%a2-%a4                 | displaced
        lea     28(%sp),%sp                       | displaced
        jmp     KINIT_RESUME

        | ------------------------------------------------------------------
        | dtyp_text: param_value_text once the value has been accepted, over
        | `lea %a2@(20),%a0; movel %d3,%sp@(32)`, both re-emitted (0008's
        | site; the two exclude each other): d4 the id, d2 the value in 8.8,
        | d3 the output buffer, a2 the RAM record. DIST TYP goes on as stock's
        | FILTER TYP, id 49, at its index for ours; OFF is written here.
        | ------------------------------------------------------------------
        .align  2
dtyp_text:
        cmp.l   #ID_DTYP,%d4
        bne.s   9f
        move.l  %d2,%d0
        asr.l   #8,%d0
        ble.s   5f
        moveq   #T_MAX,%d1
        cmp.l   %d1,%d0
        bgt.s   5f
        lea     typ_stock,%a0
        mvz.b   (%a0,%d0.l),%d0
        lsl.l   #8,%d0
        move.l  %d0,%d2
        moveq   #ID_STOCK_TYP,%d4
        lea     PARAM_INFO+ID_STOCK_TYP*PI_STRIDE,%a2
9:      lea     20(%a2),%a0                       | displaced
        move.l  %d3,32(%sp)                       | displaced
        jmp     TEXT_RESUME
5:      move.l  %d3,%a1
        lea     txt_off,%a0
6:      move.b  (%a0)+,(%a1)+
        bne.s   6b
        movem.l (%sp),%d2-%d4/%a2-%a3             | param_value_text's epilogue
        lea     20(%sp),%sp
        rts

        | Our TYP -> stock FILTER TYP's index (LP2 0, BP 2, HP2 4, BS 5).
typ_stock:
        .byte   0, 0, 2, 4, 5
        .align  2

        | ------------------------------------------------------------------
        | cfg: the device-wide record in the persisted gap.
        |
        | cfg_mode -> d0 = srr_mode, Z set for REV. cfg_dist -> d0 = DIST
        | FILTER, Z set for OFF. Use d0, a0.
        | ------------------------------------------------------------------
        .align  2
cfg_mode:
        bsr.s   cfg_ok
        bne.s   1f
        mvz.b   CFG_MODE(%a0),%d0
        and.l   #1,%d0
        rts
1:      moveq   #0,%d0
        rts

        .align  2
cfg_dist:
        bsr.s   cfg_ok
        bne.s   1f
        mvz.b   CFG_DIST(%a0),%d0
        and.l   #1,%d0
        rts
1:      moveq   #1,%d0
        rts

        | cfg_cho -> d0 = the chorus mode, 0..2. Uses d0, a0.
        .align  2
cfg_cho:
        moveq   #CFG_CHO,%d0
        bra.s   cfg_get
cfg_phs:
        moveq   #CFG_PHS,%d0
        | cfg_get(d0 = field) -> d0 its mode, 0..2. Uses d0, a0.
cfg_get:
        move.l  %d0,-(%sp)
        bsr.s   cfg_ok
        bne.s   1f
        move.l  (%sp)+,%d0
        mvz.b   (%a0,%d0.l),%d0
        cmp.l   #2,%d0
        bls.s   2f
        moveq   #0,%d0
        rts
1:      addq.l  #4,%sp
        moveq   #0,%d0
2:      rts

        | cfg_ok -> a0 = CFG, Z set when the record is ours. Uses d0.
        .align  2
cfg_ok:
        lea     CFG,%a0
        move.l  (%a0),%d0
        cmp.l   #CFG_TAG,%d0
        bne.s   9f
        mvz.b   4(%a0),%d0
        cmp.l   #CFG_VER,%d0
9:      rts

        | cfg_set(d0 = field, d1 = value): into the record, a fresh one
        | (DIST FILTER ON, REV) first if there is none - settings first and
        | the tag last, so the interrupt never reads a tag over unwritten
        | bytes. Uses d0, a0.
        .align  2
cfg_set:
        move.l  %d0,-(%sp)
        bsr.s   cfg_ok
        beq.s   1f
        moveq   #0,%d0
        move.l  %d0,4(%a0)
        move.l  %d0,8(%a0)
        moveq   #CFG_VER,%d0
        move.b  %d0,4(%a0)
        moveq   #1,%d0
        move.b  %d0,CFG_DIST(%a0)
        move.l  #CFG_TAG,%d0
        move.l  %d0,(%a0)
1:      move.l  (%sp)+,%d0
        move.b  %d1,(%a0,%d0.l)
        rts

        | ------------------------------------------------------------------
        | cave24 (.dfm): the AUDIO ROUTING item, UI context only. Calls back
        | into .text by jsr: the two pools are too far apart for bsr.w.
        | ------------------------------------------------------------------
        .section .dfm,"ax"

        | ------------------------------------------------------------------
        | dfm_menu: AudioRoutingMenuView's item list, over `movel %d7,%sp@-;
        | movel %a4,%sp@-; moveal %a0@(28),%a0`, the start of the call of the
        | view's vtable +28. 0013's DAC SUM (whose detour rejoins here) has
        | just loaded a0 with the vtable and pushed 2, the call's last
        | argument; both are taken back, DIST FILTER is appended with DAC
        | SUM's sequence at the depth it runs at, and the call is set up
        | again. a4 the view, a5 the MenuItem constructor, a2 the
        | std::function destructor, d2..d5 the four functions' slots; d7 is
        | kept. d6 and fp are free: the host's epilogue restores them.
        | ------------------------------------------------------------------
        .align  2
dfm_menu:
        addq.l  #4,%sp                            | the 2, pushed again below
        move.l  (%a4),%a0
        move.l  8(%a0),%fp                        | append
        clr.l   76(%sp)
        pea     0x1
        jsr     mem_new
        clr.l   96(%sp)
        clr.l   112(%sp)
        move.l  %d0,72(%sp)
        move.l  #dfm_label,%d0
        move.l  %d0,84(%sp)
        move.l  #MGR_LABEL,%d0
        move.l  %d0,80(%sp)
        pea     0x1
        jsr     mem_new
        clr.l   132(%sp)
        move.l  %d0,108(%sp)
        move.l  #dfm_draw,%d0
        move.l  %d0,120(%sp)
        move.l  #MGR_DRAW,%d0
        move.l  %d0,116(%sp)
        lea     32(%sp),%sp
        pea     0x1
        move.l  %a4,%d0                           | the view, stored in place
        move.l  %d0,96(%sp)
        move.l  #dfm_change,%d0
        move.l  %d0,108(%sp)
        move.l  #dfm_mgr,%d0
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
        move.l  %d7,-(%sp)                        | displaced
        move.l  %a4,-(%sp)                        | displaced
        move.l  28(%a0),%a0                       | displaced
        jmp     MENU_RESUME

        | dfm_label(a0 = the std::string to construct) -> d0 = a0.
        .align  2
dfm_label:
        link.w  %fp,#-4
        move.l  %d2,-(%sp)
        pea     -1(%fp)
        pea     txt_dfm
        move.l  %a0,%d2
        move.l  %a0,-(%sp)
        jsr     std_string_from_cstr
        lea     12(%sp),%sp
        move.l  %d2,%d0
        move.l  -8(%fp),%d2
        unlk    %fp
        rts

        | dfm_draw(functor, -, canvas, x, y): ON or OFF, right-aligned at
        | x + 19, as DAC SUM's.
        .align  2
dfm_draw:
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
        jsr     cfg_dist
        move.l  #txt_off,%d2
        tst.l   %d0
        beq.s   1f
        move.l  #txt_on,%d2
1:      move.l  %d4,-(%sp)
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

        | dfm_change(functor, -, delta): up turns DIST FILTER on, down off,
        | then the view the functor holds is invalidated.
        .align  2
dfm_change:
        move.l  12(%sp),%d0
        beq.s   9f
        moveq   #0,%d1
        tst.l   %d0
        bmi.s   1f
        moveq   #1,%d1
1:      moveq   #CFG_DIST,%d0
        jsr     cfg_set
        move.l  4(%sp),%a0
        move.l  (%a0),%a0                         | the view
        pea     56(%a0)
        jsr     VIEW_INVALIDATE
        addq.l  #4,%sp
9:      rts

        | dfm_mgr(dest, source, op): the changer's std::function manager, for
        | a functor stored in place - the view pointer - as 0013's dac_mgr.
        .align  2
dfm_mgr:
        move.l  4(%sp),%a0                        | dest
        move.l  12(%sp),%d0                       | op
        bne.s   1f
        move.l  #dfm_mgr,(%a0)
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

        | ------------------------------------------------------------------
        | The records' names and the menu's texts, back in .text.
        | ------------------------------------------------------------------
        .text
txt_srr_long:
        .asciz  "Sample Rate Red."
txt_dfrq_long:
        .asciz  "Dist Filter Freq"
txt_dres_long:
        .asciz  "Dist Filter Res"
txt_dtyp_long:
        .asciz  "Dist Filter Type"
txt_dfrq_short:
        .asciz  "FRQ"
txt_dres_short:
        .asciz  "RES"
txt_dtyp_short:
        .asciz  "TYP"
txt_dfm:
        .asciz  "DIST FILTER"
txt_on:
        .asciz  "ON"
txt_off:
        .asciz  "OFF"

        | ------------------------------------------------------------------
        | State, written at run time.
        | ------------------------------------------------------------------
        .align  2
txt_srr_short:                                    | rewritten by srr_label
        .byte   0x53, 0x52, 0x52, 0, 0, 0, 0, 0
srr_rev:
        .long   0, 0, 0                           | count, held L, held R
srr_dly:
        .long   0, 0, 0
srr_mpre:
        .long   0, 0, 0
srr_mpost:
        .long   0, 0, 0
df_key:
        .long   -1
df_coefs:
        .long   0, 0, 0, 0, 0                     | b0, b1, b2, -a1, -a2
df_state:
        .long   0, 0, 0, 0, 0, 0, 0, 0            | L then R: x1, x2, y1, y2
mom_on:
        .byte   0
mom_key:
        .byte   0x71                              | the pressed SRR encoder's key
        .align  2
txt_chr_short:                                    | REVERB 2 D: 12B
        .byte   0x31, 0x32, 0x42, 0, 0, 0, 0, 0
txt_phs_short:
        .byte   0x50, 0x48, 0x2d, 0, 0, 0, 0, 0
cho_names:
        .byte   0x43, 0x48, 0x4f, 0               | CHO (no setting yet: the reverb)
        .byte   0x43, 0x48, 0x4f, 0               | CHO
        .byte   0x43, 0x48, 0x4f, 0x2e            | CHO.
phs_names:
        .byte   0x50, 0x48, 0x2d, 0               | PH-
        .byte   0x50, 0x48, 0x53, 0               | PHS
        .byte   0x50, 0x48, 0x53, 0x2e            | PHS.
        .align  2

        | ------------------------------------------------------------------
        | cave3: cos and sin of w0 = 2 pi fc / 48000 at FRQ's fc = 13.75 *
        | 2^(FRQ / 12), Q31.
        | ------------------------------------------------------------------
        .text
        .align  2
        | The REVERB view's page vector: REVERB, then REVERB 2 (page 14, which
        | 0013's page_info answers).
rev_pages:
        .long   9, 14
        .align  2

        .section .dft,"a"
        .align  2
        .include "mods/0019-reverb-srr/df_cos_sin.inc"

        | ------------------------------------------------------------------
        | cave5: 1 / (2 Q), Q15, Q = 0.707 (2 / 0.707)^(RES / 127) and
        | 0.5 * 16^(RES / 127).
        | ------------------------------------------------------------------
        .section .dfk,"a"
        .align  2
        .include "mods/0019-reverb-srr/df_kq.inc"

        | ------------------------------------------------------------------
        | REVERB 2's own values, the phaser and the chorus (cave31, the
        | hidden BD FM 2 machine's routine; its entry points at DISABLE).
        |
        | REVERB 2 is BIT (446, FX word 41) and seven values that are not FX
        | words - all 42 are taken - so not lockable: SRR, HIS, CHR, DEP, CMB,
        | CMK, RNG, records 334..340 (BD HARD 2's, kind REVERB, words 42..48,
        | which stock's FX get and write refuse) with modflags 0, and
        | FxParameterSet's get (+0x28) and write (+0x30) wrapped to keep them
        | in rv2_val. The kit carries them in the stored FX block's
        | +0x64..+0x6b, which stock's FX save zeroes and its load never
        | reads: a tag, then the seven.
        |
        | ph_go, the phaser, REVERB's encoder G (FX word 29, lockable): the
        | rate, 0 off, 0.03..8 Hz; four allpasses on the mono sum at 24 kHz,
        | the corner swept about 200 Hz..4.5 kHz, feedback 0.7, half dry and
        | half wet, the change added to both sides. On the reverb's output or
        | the delay's input by the encoder's press.
        |
        | cho_go, the chorus, REVERB 2's CHR (rate, 0 off) and DEP (the sweep,
        | to 16 ms): a 7 ms delay swept on a triangle, right half a turn after
        | left, 60 % wet, at 48 kHz; on the reverb or the delay's input by
        | CHR's press. The delays are worked out once a block and slid.
        |
        | rv2_go, on the reverb's output last, at 24 kHz (a pair of frames at
        | a time), each by its press on the reverb or the delay's input, each
        | costing nothing at 0. LITE: the comb (CMB, CMK) and the octaver are
        | gone; in order:
        |   DRK (E)  darken, a one-pole lowpass a side, c = (140 - v)^2 27/16
        |            (about 7 kHz at 1, 2.7 kHz at 64, 70 Hz at 127)
        |   SAT (F)  saturation, u = clamp(x (1 + v / 16)), u (1.5 - u^2 / 2)
        |   RNG (H)  a ring modulator, a sine at 20 * 2^(RNG / 16) Hz (20
        |            Hz..4.8 kHz) times the whole return
        |   TRM (G)  auto-pan at 0.1 * 2^(v / 16) Hz (0.1..24 Hz): the side the
        |            pan leaves is turned down, the other kept, no centre dip
        |   WID (A)  stereo width, the side signal times 1 + v / 32
        |   HIS (C)  hiss to -42 dB
        |
        | ------------------------------------------------------------------
        .equ    ID_R2,          334
        .equ    R2N,            8                 | records 334..341
        .equ    R2S,            7                 | of them kept in +0x65..+0x6b; OCT in DIST's
        .equ    ID_REF,         410               | a plain 0..127 record, as 0021's DG knobs take
        .equ    R2OFF,          0x64
        .equ    R2TAG,          0xab              | lite: 0xaa kits load the reused slots at 0
        .equ    R2TAG_OLD,      0xaa
        .equ    FXGET_STOCK,    0x400a8e90
        .equ    FXPUT_STOCK,    0x400a9ebc
        .equ    CHOBUF,         0x4B700000        | 2048 frames, L and R words, 8 KB
        .equ    CHO_MASK,       2047
        .equ    CHO_BASE,       336               | 7 ms
        .equ    V_SRR,          0                 | rv2_val, byte offsets
        .equ    V_HIS,          2
        .equ    V_CHR,          4
        .equ    V_DEP,          6                 | lite: DRK (E)
        .equ    V_CMB,          8                 | lite: SAT (F)
        .equ    V_CMK,          10                | lite: TRM (G)
        .equ    V_RNG,          12
        .equ    V_OCT,          14                | lite: WID (A)
        .equ    S_CON,          0                 | rv2_st
        .equ    S_CWP,          4
        .equ    S_PPH,          8
        .equ    S_RPH,          12
        .equ    S_PPREV,        16
        .equ    S_SEED,         20
        .equ    S_HON,          24
        .equ    S_HWP,          28
        .equ    S_HPH,          32
        .equ    S_PX,           36                | the phaser: x1, y1 for four stages
        .equ    S_PLAST,        68
        .equ    S_PREV,         72                | the comb's last change
        .equ    S_CNT,          76
        .equ    S_HDL,          80                | the chorus delays, 16.16
        .equ    S_HDR,          84
        .equ    S_DR,           88
        .equ    S_DRL,          100               | lite: DRK's lowpass, left
        .equ    S_DRR,          104               | and right
        .equ    S_TPH,          108               | TRM's phase
        .equ    P_DRK,          0                 | rv2_prm: DRK's coefficient, Q15
        .equ    P_SAT,          4                 | SAT's drive, Q8
        .equ    P_PAL,          8
        .equ    P_RINC,         12
        .equ    P_HIS,          16
        .equ    P_CDEP,         20
        .equ    P_CINC,         24
        .equ    P_MIX,          28                | 0.6, Q14
        .equ    P_WID,          32                | WID's side gain, Q8
        .equ    P_TRM,          36                | TRM's step a pair

        .section .rv2,"ax"
        .align  2

        | fxs_get(set, id) -> d0: ours from rv2_val, else stock's.
fxs_get:
        move.l  8(%sp),%d0
        sub.l   #ID_R2,%d0
        moveq   #R2N,%d1
        cmp.l   %d1,%d0
        bcc.s   1f
        lea     rv2_val,%a0
        mvz.w   (%a0,%d0.l*2),%d0
        rts
1:      jmp     FXGET_STOCK

        | fxs_put(set, id, value, ...): ours into rv2_val, else stock's.
fxs_put:
        move.l  8(%sp),%d0
        sub.l   #ID_R2,%d0
        moveq   #R2N,%d1
        cmp.l   %d1,%d0
        bcc.s   1f
        lea     rv2_val,%a0
        move.l  12(%sp),%d1
        move.w  %d1,(%a0,%d0.l*2)
        rts
1:      jmp     FXPUT_STOCK

        .section .ph,"ax"                         | lite: the phaser, out of cave31
        .align  2
        | ------------------------------------------------------------------
        | ph_go(a1 32 stereo frames): the phaser at FX word 29's rate, a pair
        | of frames at a time on their mono sum; the change (out - in) is
        | added to both sides, the pair's first frame taking the mean of the
        | last pair's and this one's. Uses d0..d7, a0, a2, a3; keeps a4..a6.
        | ------------------------------------------------------------------
ph_go:
        lea     rv2_prm,%a2
        lea     rv2_st,%a3
        mvs.w   PHS_WORD,%d0
        asr.l   #8,%d0
        bgt.s   1f
        clr.l   S_PPREV(%a3)
        rts
1:      moveq   #VMAX,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      addq.l  #8,%d0
        muls.w  %d0,%d0
        muls.w  #39,%d0
        lsl.l   #5,%d0                            | a block's step
        add.l   S_PPH(%a3),%d0
        move.l  %d0,S_PPH(%a3)
        bpl.s   3f                                | the coefficient, once a block:
        not.l   %d0                               | -0.949 + 0.749 tri^2 at 24 kHz
3:      moveq   #15,%d1
        lsr.l   %d1,%d0
        mulu.l  %d0,%d0
        clr.w   %d0
        swap    %d0
        move.l  #24543,%d1
        mulu.l  %d1,%d0
        clr.w   %d0
        swap    %d0
        sub.l   #31097,%d0
        move.l  %d0,%d6                           | a
        moveq   #FRAMES/2,%d0
        move.l  %d0,S_CNT(%a3)
4:      move.l  (%a1),%d0                         | a pair: l0, r0, l1, r1
        asr.l   #8,%d0
        asr.l   #8,%d0
        move.l  4(%a1),%d1
        asr.l   #8,%d1
        asr.l   #8,%d1
        move.l  8(%a1),%d2
        asr.l   #8,%d2
        asr.l   #8,%d2
        move.l  12(%a1),%d3
        asr.l   #8,%d3
        asr.l   #8,%d3
        add.l   %d1,%d0
        add.l   %d3,%d2
        add.l   %d2,%d0
        asr.l   #2,%d0                            | the mono sum, 16 bits
        movea.l %d0,%a0
        move.l  S_PLAST(%a3),%d1                  | x + 0.7 last
        move.l  #22938,%d2
        muls.l  %d2,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        add.l   %d0,%d1
        lea     S_PX(%a3),%a2
        .rept   4
        move.l  %d1,%d2                           | y = x1 + a (x - y1)
        sub.l   4(%a2),%d2
        muls.l  %d6,%d2
        asr.l   #8,%d2
        asr.l   #7,%d2
        add.l   (%a2),%d2
        move.l  %d1,(%a2)+
        move.l  %d2,(%a2)+
        move.l  %d2,%d1
        .endr
        lea     rv2_prm,%a2
        move.l  %d1,S_PLAST(%a3)
        add.l   %d1,%d0
        asr.l   #1,%d0                            | half and half
        sub.l   %a0,%d0                           | the change
        move.l  S_PPREV(%a3),%d1
        move.l  %d0,S_PPREV(%a3)
        add.l   %d0,%d1
        asr.l   #1,%d1                            | the first frame's: the mean
        swap    %d1
        clr.w   %d1
        swap    %d0
        clr.w   %d0
        .irp    o,0,4
        move.l  \o(%a1),%d2
        add.l   %d1,%d2
        bvc.s   5f
        bsr.w   r2_sat
5:      move.l  %d2,\o(%a1)
        .endr
        .irp    o,8,12
        move.l  \o(%a1),%d2
        add.l   %d0,%d2
        bvc.s   5f
        bsr.w   r2_sat
5:      move.l  %d2,\o(%a1)
        .endr
        lea     16(%a1),%a1
        subq.l  #1,S_CNT(%a3)
        bne.w   4b
        rts

        | r2_sat(d2 an overflowed sum) -> d2 full scale of its true sign
        | (the overflow flipped it). Uses nothing else.
r2_sat:
        tst.l   %d2
        bmi.s   1f
        move.l  #0x80000000,%d2
        rts
1:      move.l  #0x7fffffff,%d2
        rts

        .section .rv2,"ax"
        .align  2

        | ------------------------------------------------------------------
        | rv2_go(a1 the return, 32 stereo frames): DRK, SAT, RNG, TRM, WID,
        | HIS, those rv2_mask places here, a pair of frames at a time.
        | Uses d0..d7, a0, a2, a3; keeps a4..a6.
        | ------------------------------------------------------------------
rv2_go:
        lea     rv2_val,%a0
        lea     rv2_prm,%a2
        lea     rv2_st,%a3
        moveq   #0,%d7                            | bits: 0 SAT, 1 RNG, 2 WID, 3 HIS, 4 TRM, 5 DRK
        mvz.w   V_CMB(%a0),%d0                    | SAT: 1 + v / 16, Q8
        lsr.l   #8,%d0
        beq.s   1f
        bset    #0,%d7
        lsl.l   #4,%d0
        add.l   #256,%d0
        move.l  %d0,P_SAT(%a2)
1:      mvz.w   V_RNG(%a0),%d0
        lsr.l   #8,%d0
        beq.s   2f
        bset    #1,%d7
        move.l  %d0,%d1
        moveq   #15,%d2
        and.l   %d2,%d1
        lea     pow16,%a3
        mvz.w   (%a3,%d1.l*2),%d1                 | 256 * 2^(k / 16)
        muls.w  #13981,%d1                        | 20 Hz at 24 kHz, >> 8
        lsr.l   #4,%d0
        lsl.l   %d0,%d1                           | the carrier's step
        move.l  %d1,P_RINC(%a2)
2:      mvz.w   V_HIS(%a0),%d0
        lsr.l   #8,%d0
        beq.s   3f
        bset    #3,%d7
        muls.w  %d0,%d0
        lsr.l   #6,%d0                            | to 252, Q15: -42 dB
        move.l  %d0,P_HIS(%a2)
3:      mvz.w   V_OCT(%a0),%d0                    | WID: 1 + v / 32, Q8
        lsr.l   #8,%d0
        beq.s   4f
        bset    #2,%d7
        lsl.l   #3,%d0
        add.l   #256,%d0
        move.l  %d0,P_WID(%a2)
4:      mvz.w   V_CMK(%a0),%d0                    | TRM: 0.1 * 2^(v / 16) Hz
        lsr.l   #8,%d0
        beq.s   5f
        bset    #4,%d7
        move.l  %d0,%d1
        moveq   #15,%d2
        and.l   %d2,%d1
        lea     pow16,%a3
        mvz.w   (%a3,%d1.l*2),%d1
        muls.w  #70,%d1                           | 0.1 Hz at 24 kHz, >> 8
        lsr.l   #4,%d0
        lsl.l   %d0,%d1
        move.l  %d1,P_TRM(%a2)
5:      mvz.w   V_DEP(%a0),%d0                    | DRK: (140 - v)^2 27 / 16, Q15
        lsr.l   #8,%d0
        beq.s   6f
        bset    #5,%d7
        neg.l   %d0
        add.l   #140,%d0
        muls.w  %d0,%d0
        muls.w  #27,%d0
        lsr.l   #4,%d0
        cmp.l   #32767,%d0
        bls.s   51f
        move.l  #32767,%d0
51:     move.l  %d0,P_DRK(%a2)
6:      lea     rv2_st,%a3
        and.l   rv2_mask,%d7                      | those in this place
        bne.s   7f
        rts
7:      moveq   #FRAMES/2,%d0
        move.l  %d0,S_CNT(%a3)

8:      move.l  (%a1),%d0                         | a pair: l0, r0, l1, r1
        swap    %d0
        ext.l   %d0
        move.l  4(%a1),%d1
        swap    %d1
        ext.l   %d1
        move.l  8(%a1),%d2
        swap    %d2
        ext.l   %d2
        move.l  12(%a1),%d3
        swap    %d3
        ext.l   %d3

        btst    #5,%d7                            | DRK: y += c (x - y), a side
        beq.w   20f
        move.l  P_DRK(%a2),%d6
        move.l  S_DRL(%a3),%d4
        move.l  S_DRR(%a3),%d5
        .irp    r,%d0,%d2
        sub.l   %d4,\r
        muls.l  %d6,\r
        asr.l   #8,\r
        asr.l   #7,\r
        add.l   %d4,\r
        move.l  \r,%d4
        .endr
        .irp    r,%d1,%d3
        sub.l   %d5,\r
        muls.l  %d6,\r
        asr.l   #8,\r
        asr.l   #7,\r
        add.l   %d5,\r
        move.l  \r,%d5
        .endr
        move.l  %d4,S_DRL(%a3)
        move.l  %d5,S_DRR(%a3)

20:     btst    #0,%d7                            | SAT
        beq.w   30f
        move.l  P_SAT(%a2),%d6
        .irp    r,%d0,%d1,%d2,%d3
        muls.l  %d6,\r
        asr.l   #8,\r
        cmp.l   #32767,\r
        ble.s   1f
        move.l  #32767,\r
1:      cmp.l   #-32767,\r
        bge.s   2f
        move.l  #-32767,\r
2:      move.l  \r,%d4
        muls.l  %d4,%d4
        clr.w   %d4
        swap    %d4
        neg.l   %d4
        add.l   #49152,%d4                        | 1.5 - u^2 / 2
        muls.l  %d4,\r
        asr.l   #8,\r
        asr.l   #7,\r
        .endr

30:     btst    #1,%d7                            | RNG: a sine, a pair's
        beq.w   40f
        move.l  S_RPH(%a3),%d4
        add.l   P_RINC(%a2),%d4
        move.l  %d4,S_RPH(%a3)
        swap    %d4
        ext.l   %d4                               | x, -32768..32767 for -pi..pi
        move.l  %d4,%d5
        bpl.s   31f
        neg.l   %d5
31:     neg.l   %d5
        add.l   #32768,%d5
        muls.l  %d5,%d4
        moveq   #13,%d5
        asr.l   %d5,%d4                           | 4x(1 - |x|), Q15
        .irp    r,%d0,%d1,%d2,%d3
        muls.l  %d4,\r
        asr.l   #8,\r
        asr.l   #7,\r
        .endr

40:     btst    #4,%d7                            | TRM: the pan, a pair's
        beq.w   45f
        move.l  S_TPH(%a3),%d4
        add.l   P_TRM(%a2),%d4
        move.l  %d4,S_TPH(%a3)
        swap    %d4
        ext.l   %d4
        move.l  %d4,%d5
        bpl.s   41f
        neg.l   %d5
41:     neg.l   %d5
        add.l   #32768,%d5
        muls.l  %d5,%d4
        moveq   #13,%d5
        asr.l   %d5,%d4                           | p, -1..1, Q15
        move.l  #32768,%d5                        | gL in d5, gR in d6
        move.l  %d5,%d6
        tst.l   %d4
        bmi.s   42f
        sub.l   %d4,%d5                           | to the right: left down
        bra.s   43f
42:     add.l   %d4,%d6                           | to the left: right down
43:     .irp    r,%d0,%d2
        muls.l  %d5,\r
        asr.l   #8,\r
        asr.l   #7,\r
        .endr
        .irp    r,%d1,%d3
        muls.l  %d6,\r
        asr.l   #8,\r
        asr.l   #7,\r
        .endr

45:     btst    #2,%d7                            | WID: m + s w, m - s w
        beq.w   47f
        move.l  P_WID(%a2),%d6
        move.l  %d0,%d4
        add.l   %d1,%d4
        asr.l   #1,%d4                            | m
        sub.l   %d1,%d0
        asr.l   #1,%d0                            | s
        muls.l  %d6,%d0
        asr.l   #8,%d0
        move.l  %d4,%d1
        sub.l   %d0,%d1
        add.l   %d4,%d0
        move.l  %d2,%d4
        add.l   %d3,%d4
        asr.l   #1,%d4
        sub.l   %d3,%d2
        asr.l   #1,%d2
        muls.l  %d6,%d2
        asr.l   #8,%d2
        move.l  %d4,%d3
        sub.l   %d2,%d3
        add.l   %d4,%d2

47:     btst    #3,%d7
        beq.w   50f
        move.l  S_SEED(%a3),%d4                   | the hiss, a pair's
        move.l  #1664525,%d5
        mulu.l  %d5,%d4
        add.l   #1013904223,%d4
        move.l  %d4,S_SEED(%a3)
        move.l  %d4,%d5
        swap    %d4
        ext.l   %d4                               | left: bits 16..31
        lsl.l   #8,%d5
        swap    %d5
        ext.l   %d5                               | right: bits 8..23
        move.l  P_HIS(%a2),%d6
        muls.l  %d6,%d4
        asr.l   #8,%d4
        asr.l   #7,%d4
        muls.l  %d6,%d5
        asr.l   #8,%d5
        asr.l   #7,%d5
        add.l   %d4,%d0
        add.l   %d4,%d2
        add.l   %d5,%d1
        add.l   %d5,%d3

50:     move.l  #32767,%d4                        | clip, store
        move.l  %d4,%d5
        neg.l   %d5
        .irp    r,%d0,%d1,%d2,%d3
        cmp.l   %d4,\r
        ble.s   1f
        move.l  %d4,\r
1:      cmp.l   %d5,\r
        bge.s   2f
        move.l  %d5,\r
2:      swap    \r
        clr.w   \r
        move.l  \r,(%a1)+
        .endr
        subq.l  #1,S_CNT(%a3)
        bne.w   8b
        rts

        .section .rv2,"ax"

        .align  2
rv2_val:
        .word   0, 0, 0, 0, 0, 0, 0, 0
rv2_def:
        .word   0, 0, 0, 0, 0, 0, 0, 0
rv2_st:
        .long   0, 0, 0, 0, 0, 0x2545f491, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
rv2_prm:
        .long   0, 0, 0, 0, 0, 0, 0, 9830, 0, 0
oct_ld:
        .word   0
        .align  2
txt_r2oct_l:    .asciz  "Width"
        .align  2
        | REVERB 2's short names that r2_label marks, 8 bytes each, in
        | r2_slot's order (lite: OCT is WID, CMB SAT, CMK TRM, DEP DRK).
txt_r2oct_s:    .ascii  "WID\0\0\0\0\0"
txt_r2his_s:    .ascii  "HIS\0\0\0\0\0"
txt_r2cmb_s:    .ascii  "SAT\0\0\0\0\0"
txt_r2cmk_s:    .ascii  "TRM\0\0\0\0\0"
txt_r2rng_s:    .ascii  "RNG\0\0\0\0\0"
txt_r2dep_s:    .ascii  "DRK\0\0\0\0\0"
r2_slot:                                          | each name's route bit
        .byte   2, 3, 0, 4, 1, 5
        | Each record's route bit, 334..341, -1 none (SRR and 12B have their own).
r2_rbit:
        .byte   -1, 3, -1, 5, 0, 4, 1, 2
        .align  2
rv2_mask:
        .long   0

        | cfg_r2r -> d0 REVERB 2's route mask (bit 0 SAT, 1 RNG, 2 WID, 3 HIS,
        | 4 TRM, 5 DRK; set: on the delay's input), 0 without a record. Uses
        | d0, a0.
cfg_r2r:
        jsr     cfg_ok
        bne.s   1f
        mvz.b   CFG_R2R(%a0),%d0
        rts
1:      moveq   #0,%d0
        rts

        | r2_label: a dot after the short name of each of those on the delay.
        | Uses d0, d1, a0, a1.
r2_label:
        move.l  %d2,-(%sp)
        jsr     cfg_r2r
        lea     r2_slot,%a1
        lea     txt_r2oct_s+3,%a0
        moveq   #6,%d2
1:      mvz.b   (%a1)+,%d1
        btst    %d1,%d0
        sne     %d1
        and.l   #DOT,%d1
        move.b  %d1,(%a0)
        addq.l  #8,%a0
        subq.l  #1,%d2
        bne.s   1b
        move.l  (%sp)+,%d2
        rts

        | ------------------------------------------------------------------
        | In cave8 with knob_key: the kit's save and load of the seven, the
        | tables and the names.
        | ------------------------------------------------------------------
        .section .kk,"ax"
        | cho_label: the chorus rate's and the phaser's short names by their
        | modes: "CH-" off, "CHO" on the reverb, "CHO." on the delay's input;
        | "PH-", "PHS", "PHS.". Uses d0, d1, a0.
        .align  2
cho_label:
        jsr     cfg_phs
        lea     phs_names,%a0
        move.l  (%a0,%d0.l*4),%d1
        lea     txt_phs_short,%a0
        move.l  %d1,(%a0)
        rts

        .align  2
        .align  2

        | rv2_save(a2 the stored FX block): the tag, then the seven bytes.
        | Uses d0, a1.
rv2_save:
        move.l  %d1,-(%sp)
        lea     rv2_val,%a1
        moveq   #R2TAG-256,%d0
        move.b  %d0,R2OFF(%a2)
        moveq   #0,%d1
1:      move.b  (%a1,%d1.l*2),%d0
        move.b  %d0,R2OFF+1(%a2,%d1.l)
        addq.l  #1,%d1
        moveq   #R2S,%d0
        cmp.l   %d0,%d1
        blt.s   1b
        move.l  (%sp)+,%d1
        rts

        | rv2_load(a1 the stored FX block): tagged, the seven bytes; else the
        | defaults. Uses d0, d1, a0.
rv2_load:
        mvz.b   R2OFF(%a1),%d0
        cmp.l   #R2TAG,%d0
        beq.s   0f
        cmp.l   #R2TAG_OLD,%d0
        bne.s   rv2_init
0:      move.l  %d0,-(%sp)
        lea     rv2_val,%a0
        moveq   #1,%d1
1:      mvz.b   R2OFF(%a1,%d1.l),%d0
        and.l   #0x7f,%d0
        lsl.l   #8,%d0
        move.w  %d0,-2(%a0,%d1.l*2)
        addq.l  #1,%d1
        moveq   #R2S+1,%d0
        cmp.l   %d0,%d1
        blt.s   1b
        move.l  (%sp)+,%d0
        cmp.l   #R2TAG,%d0
        beq.s   2f
        moveq   #0,%d0                            | lite: a kit from before reads
        move.w  %d0,V_DEP(%a0)                    | DRK, SAT and TRM as 0 (they
        move.w  %d0,V_CMB(%a0)                    | held the chorus depth and
        move.w  %d0,V_CMK(%a0)                    | the comb)
2:      rts

        | rv2_init: the records' defaults. Uses d0, a0.
rv2_init:
        lea     rv2_val,%a0
        move.l  rv2_def,%d0
        move.l  %d0,(%a0)
        move.l  rv2_def+4,%d0
        move.l  %d0,4(%a0)
        move.l  rv2_def+8,%d0
        move.l  %d0,8(%a0)
        move.l  rv2_def+12,%d0
        move.l  %d0,12(%a0)
        rts

        .align  2
pow16:                                            | 256 * 2^(k / 16)
        .word   256, 267, 279, 292, 304, 318, 332, 347, 362, 378, 395, 412, 431, 450, 470, 490
txt_r2his_l:    .asciz  "Hiss"
txt_r2dep_l:    .asciz  "Darken"
txt_r2cmb_l:    .asciz  "Saturate"
txt_r2cmk_l:    .asciz  "Tremolo"
txt_r2rng_l:    .asciz  "Ring Mod"
txt_r2chr_l:    .asciz  "12-Bit FX"
txt_phs_long:   .asciz  "Phaser Rate"
        .align  2

        | ------------------------------------------------------------------
        | PANIC (cave14). Stock's all-sound-off (0x4009c92a, from CC 120, the
        | double STOP's paths and others) first asks the audio interrupt to
        | fade the output out, waits until it is silent (or a timeout), puts
        | this mod's effects back to rest - the crusher holds, the DIST
        | filter's history, REVERB 2's state (its lines are cleared again as
        | they come on) - and clears the delay's 2 MB ring, then goes on as
        | stock. The interrupt (pnc_go, from fx_post) fades the output ring's
        | PRE and POST pairs over 48 samples (1 ms), holds them silent for
        | PNC_HOLD blocks, and fades them in again over 1 ms. Only the
        | interrupt moves pnc_state past 1, so the two never race.
        | ------------------------------------------------------------------
        .equ    PNC_STEP,       683               | 32768 / 48: 1 ms
        .equ    PNC_HOLD,       60                | blocks silent: 40 ms
        .equ    PNC_WAIT,       2000000           | the task's wait, a few ms
        .equ    PNC_RESUME,     0x4009c930
        .equ    DLY_RING,       0x4B400000        | 2 MB with 0022
        .equ    DLY_BYTES,      0x200000

        .section .pnc,"ax"
        .align  2
        | pnc_entry: over `movel %a2,%sp@-; movel %d2,%sp@-; clrl %d2`, the
        | routine's start, re-emitted. d0, d1, a0, a1 are the caller's to lose.
pnc_entry:
        tst.l   pnc_state
        bne.s   2f                                | already fading: just clear
        moveq   #1,%d0
        move.l  %d0,pnc_state
        move.l  #PNC_WAIT,%d1
1:      moveq   #1,%d0
        cmp.l   pnc_state,%d0
        bne.s   2f
        subq.l  #1,%d1
        bne.s   1b
2:      moveq   #0,%d0
        lea     srr_rev,%a0                       | the four holds
        moveq   #12,%d1
3:      move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bne.s   3b
        lea     df_state,%a0
        moveq   #8,%d1
4:      move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bne.s   4b
        move.l  rv2_st+S_SEED,-(%sp)
        lea     rv2_st,%a0
        moveq   #26,%d1
5:      move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bne.s   5b
        move.l  (%sp)+,%d1
        move.l  %d1,rv2_st+S_SEED
        lea     DLY_RING,%a0
        move.l  #DLY_BYTES/32,%d1
6:      .rept   8
        move.l  %d0,(%a0)+
        .endr
        subq.l  #1,%d1
        bne.s   6b
        move.l  %a2,-(%sp)                        | displaced
        move.l  %d2,-(%sp)
        clr.l   %d2
        jmp     PNC_RESUME

        | pnc_go(a6 this block's ring slot): the fade. 0 idle (untouched),
        | 1 fading out, 2 silent for pnc_hold blocks, 4 fading in. Uses d0..d5,
        | a1.
pnc_go:
        move.l  pnc_state,%d0
        beq.w   9f
        move.l  %d0,%d4
        move.l  pnc_gain,%d1
        moveq   #2,%d2
        cmp.l   %d2,%d0
        bne.s   1f
        subq.l  #1,pnc_hold
        bne.s   1f
        moveq   #4,%d0                            | the hold is over
1:      lea     OUT_PRE(%a6),%a1
        moveq   #FRAMES,%d5
2:      moveq   #1,%d2
        cmp.l   %d2,%d0
        bne.s   3f
        sub.l   #PNC_STEP,%d1
        bgt.s   5f
        moveq   #0,%d1
        moveq   #2,%d0
        bra.s   5f
3:      moveq   #4,%d2
        cmp.l   %d2,%d0
        bne.s   5f
        add.l   #PNC_STEP,%d1
        cmp.l   #32768,%d1
        blt.s   5f
        move.l  #32768,%d1
        moveq   #0,%d0
5:      cmp.l   #32768,%d1
        beq.s   7f
        .irp    o,0,4,8,12
        move.l  \o(%a1),%d2
        swap    %d2
        ext.l   %d2
        muls.l  %d1,%d2
        lsl.l   #1,%d2
        move.l  %d2,\o(%a1)
        .endr
7:      lea     OUT_STRIDE(%a1),%a1
        subq.l  #1,%d5
        bne.w   2b
        move.l  %d1,pnc_gain
        cmp.l   %d4,%d0
        beq.s   9f
        moveq   #2,%d2
        cmp.l   %d2,%d0
        bne.s   8f
        moveq   #PNC_HOLD,%d2
        move.l  %d2,pnc_hold
8:      move.l  %d0,pnc_state
9:      rts

        | b12_go(a1 32 stereo frames): with REVERB 2's 12B above 0, each
        | sample keeps its top 12 bits, no dither. Uses d0, d1, a1.
b12_go:
        mvz.w   rv2_val+V_CHR,%d0
        lsr.l   #8,%d0
        beq.s   9f
        move.l  #0xfff00000,%d0
        moveq   #FRAMES*2/4,%d1
1:      .rept   4
        and.l   %d0,(%a1)+
        .endr
        subq.l  #1,%d1
        bne.s   1b
9:      rts

        .align  2
pnc_state:
        .long   0
pnc_gain:
        .long   32768
pnc_hold:
        .long   0
