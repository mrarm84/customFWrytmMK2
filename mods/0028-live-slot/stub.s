        | Mod 0028 - four live loops: the recorder's buffer split in four, each a
        | sample slot (124..127) of its own track (1, 2, 5, 6).
        |
        | The stock recorder (0x4013f56c, every audio interrupt) writes the
        | recording mono at REC_BUF (16-bit words, the sample's high 16 bits)
        | and REC_LOW (its low 8), at most REC_MAX samples, and stops at the
        | target RLEN sets. State at REC_STATE: 0 idle, 1 armed, 2 recording,
        | 3 done, 4 done and normalized. SAMPLING + YES (SamplerLedView,
        | 0x40138142) arms (0 or 4), starts (1) or stops (2); SAMPLING + NO
        | discards. A finished take goes to 0x400a39e6 through the UI events:
        | the normalizer 0x4013f9dc (in place, from REC_BUF, then state 4) and
        | the SAMPLING screen's update.
        |
        | lv_sel, on entry to rec_arm and rec_start (UI context, outside states
        | 2 and 3): the selected track's region k, from lv_tracks. A loop
        | track's take goes to region k, REGION samples from REC_BUF +
        | k * REGION * 2 (and REC_LOW + k * REGION); any other track's to the
        | whole buffer, as stock.
        |   lv_wr   0x4013f828  the write's two bases (addal, addil)
        |   lv_lim1 0x4013f800  the room left: lv_lim, not REC_MAX
        |   lv_lim2 0x4013f846  the full-buffer stop: lv_lim, not REC_MAX
        |   lv_norm 0x400a39ee  a loop take is not normalized: state 4 as the
        |                       normalizer leaves it, the level as recorded
        | live_rec, on the recorder's exit (its epilogue at 0x4013f866,
        | re-emitted; 0013 owns the call site): while region k records, its
        | length is the target (clamped to the region), so a trig a few ms
        | into the take plays it as it arrives and STA/END span RLEN; once
        | done, what was recorded. Every block each region with a take points
        | its slot's table entry (0x41329e70 + 16 * slot: +0 the data, +8 the
        | length in samples, +12 the rate ratio, 1.0 = 0x40000000; the trig
        | copies these three) at it, so a project or sample reload does not
        | lose the loops. The rate word at +4 is left alone.
        .equ    REC_STATE,      0x419f0330
        .equ    REC_TARGET,     0x419f031c        | samples to record
        .equ    REC_COUNT,      0x419f0320        | samples recorded
        .equ    REC_BUF,        0x42c62190        | high 16 bits, words
        .equ    REC_LOW,        0x42adf610        | low 8 bits, bytes
        .equ    REC_MAX,        1584000           | 33 s
        .equ    REGION,         REC_MAX / 4       | 396000, 8.25 s
        .equ    SLOTS,          0x41329e70
        .equ    SLOT0,          124               | region k plays as 124 + k
        .equ    RATIO_1,        0x40000000
        .equ    NORMALIZE,      0x4013f9dc
        .equ    NORM_RESUME,    0x400a39f4
        .equ    WR_RESUME,      0x4013f834
        .equ    LIM1_RESUME,    0x4013f806
        .equ    LIM2_GO,        0x4013f85a        | below the limit: on
        .equ    LIM2_STOP,      0x4013f84e        | at it: stop
        .equ    ARM_RESUME,     0x4013f880
        .equ    START_RESUME,   0x4013f8ac
        .equ    PROJECT,        0x4017f83e        | project_singleton
        .equ    TRACK_SEL,      0x400ae426        | track_selection(project)
        .equ    TRACK_IDX,      0x400b68d2        | track_index_of(selection)

        .text
        .align  2
        | ------------------------------------------------------------------
        | live_rec: d0-d4, a0-a2 are free (the epilogue reloads d2-d4/a2).
        | ------------------------------------------------------------------
live_rec:
        move.b  lv_k,%d2
        bmi.s   5f                                | not a loop take
        ext.l   %d2
        lsl.l   #2,%d2
        lea     lv_len,%a0
        add.l   %d2,%a0
        move.l  REC_STATE,%d0
        subq.l  #2,%d0
        beq.s   1f                                | recording: the target
        subq.l  #1,%d0
        bne.s   5f
        move.l  REC_COUNT,%d1                     | done: what was recorded
        bra.s   2f
1:      move.l  REC_TARGET,%d1
        cmp.l   #REGION,%d1
        ble.s   2f
        move.l  #REGION,%d1
2:      tst.l   %d1
        ble.s   5f
        move.l  %d1,(%a0)
5:      lea     lv_len,%a0                        | every region with a take
        lea     SLOTS+16*SLOT0,%a1
        move.l  #REC_BUF,%d0
        move.l  #RATIO_1,%d3
        moveq   #4,%d4
6:      move.l  (%a0)+,%d1
        ble.s   7f
        move.l  %d0,(%a1)
        move.l  %d1,8(%a1)
        move.l  %d3,12(%a1)
7:      lea     16(%a1),%a1
        add.l   #REGION*2,%d0
        subq.l  #1,%d4
        bne.s   6b
        movem.l (%sp),%d2-%d4/%a2                 | displaced: the epilogue
        lea     16(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | lv_sel: the selected track's region, its bases and limit. UI only.
        | Leaves a take in progress (states 2 and 3) alone. d0, d1, a0, a1.
        | ------------------------------------------------------------------
lv_sel:
        move.l  REC_STATE,%d0
        subq.l  #2,%d0
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bls.s   9f                                | recording or done
        jsr     PROJECT
        move.l  %d0,-(%sp)
        jsr     TRACK_SEL
        move.l  %d0,(%sp)
        jsr     TRACK_IDX
        addq.l  #4,%sp
        moveq   #-1,%d1
        cmp.l   #12,%d0
        bcc.s   2f                                | not a sound track
        lea     lv_tracks,%a0
        move.b  (%a0,%d0.l),%d1
2:      move.b  %d1,lv_k
        move.l  #REC_BUF,%d0
        move.l  #REC_LOW,%a1
        move.l  #REC_MAX,%a0
        extb.l  %d1
        bmi.s   4f                                | the whole buffer, as stock
        move.l  #REGION,%a0
3:      subq.l  #1,%d1
        bmi.s   4f
        add.l   #REGION*2,%d0
        adda.l  #REGION,%a1
        bra.s   3b
4:      move.l  %d0,lv_hi
        move.l  %a1,lv_lo
        move.l  %a0,lv_lim
9:      rts

        | rec_arm's entry (0x4013f878): lv_sel, then its first three
        | instructions, re-emitted.
lv_arm:
        bsr.w   lv_sel
        move.l  %d2,-(%sp)
        move.w  %sr,%d1
        move.w  #0x2700,%sr
        jmp     ARM_RESUME

        | rec_start's entry (0x4013f8a6), the same.
lv_start:
        bsr.w   lv_sel
        move.l  %d3,-(%sp)
        move.l  %d2,-(%sp)
        move.w  %sr,%d3
        jmp     START_RESUME

        | The block's write: a1 = count + low base, d0 = 2 * count + high base.
lv_wr:
        adda.l  lv_lo,%a1
        add.l   lv_hi,%d0
        jmp     WR_RESUME

        | The room left, lim - count, in place of REC_MAX - count.
lv_lim1:
        move.l  lv_lim,%d0
        jmp     LIM1_RESUME

        | After the block: d2 the new count. Below lv_lim on, else stop. d0 is
        | free on both ways (reloaded at LIM2_GO, unused before the stop).
lv_lim2:
        move.l  lv_lim,%d0
        cmp.l   %d0,%d2
        blt.s   1f
        jmp     LIM2_STOP
1:      jmp     LIM2_GO

        | The finished take's normalizer call (0x400a39ee): a loop take is
        | left at its level, the state set to 4 as the normalizer would.
lv_norm:
        tst.b   lv_k
        bmi.s   1f
        moveq   #4,%d0
        move.l  %d0,REC_STATE
        jmp     NORM_RESUME
1:      jsr     NORMALIZE
        jmp     NORM_RESUME

lv_tracks:                                        | track 0..11 -> region, -1 none
        .byte   0, 1, -1, -1, 2, 3, -1, -1, -1, -1, -1, -1
lv_k:   .byte   -1                                | the take's region
        .align  2
lv_hi:  .long   REC_BUF
lv_lo:  .long   REC_LOW
lv_lim: .long   REC_MAX
lv_len: .long   0, 0, 0, 0                        | each region's take, samples
