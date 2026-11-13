        | Mod 0027 - the sample layer skips voices that would only make silence.
        |
        | 0x4011c64c, the stock sample layer, runs for each of the 8 physical
        | voices every block: a 4-point polyphase resampler over 64 steps
        | (0x4011cbae..0x4011cc52), a decimating filter (0x4011ccda..0x4011cdf0)
        | with 12 longs of state in the voice struct (+44..+91, 92 bytes a
        | voice at a3), and a level ramp into the voice's output buffer
        | (0x4011cdf2..). About 15% of a block on the unit, whether any sample
        | plays or not.
        |
        | When a voice's filter state is all zero and every input sample the
        | resampler would read is zero, both stages produce exact zeros, so:
        |   - sk_res skips the resampler, advancing the voice's position as the
        |     loop would: (hi:lo) = (0:phase) + rate << 10, 64-bit, rate signed;
        |   - sk_fir skips the filter (its state stays zero, as the write-back
        |     would leave it) and zeroes the filter's output buffer 0x8000e1d0,
        |     which the stock level ramp then turns into zeros as it would.
        | Anything else runs stock's code unchanged. The DMA bookkeeping between
        | the stages always runs.
        |
        | sk_res  detour 0x4011cbae (`movel %a3@(12),%d5; movel %d5,%d2`)
        | sk_fir  detour 0x4011ccda (`lea %a3@(44),%a0; movel %a0,%sp@-`)

        .equ    RES_RESUME,     0x4011cbb4        | stock's resampler set-up
        .equ    RES_SKIP,       0x4011cc56        | after it: the DMA bookkeeping
        .equ    FIR_RESUME,     0x4011cce0        | stock's filter
        .equ    FIR_SKIP,       0x4011cdf2        | the level ramp
        .equ    FIR_OUT,        0x8000e1d0        | the filter's output, 34 longs read
        .equ    V_POS,          4                 | voice struct: position (integer)
        .equ    V_RATE,         12                | rate, 4.28, signed
        .equ    V_PHASE,        28                | fraction
        .equ    V_ADV,          32                | the block's integer advance
        .equ    V_STATE,        44                | 12 longs of filter state

        | dbg: the block's per-voice result at SK_DBG, the last long of cave32:
        | bit v skipped, 8+v the filter state not zero, 16+v an input sample
        | not zero, 24+v backwards. Cleared at voice 0. The meter (0023)
        | sends it as words 0x68 (bits 0..15) and 0x69 (16..31).
        .equ    SK_DBG,         0x4011438c
        .equ    SP_VOICE,       88                | 0x4011c64c's frame: the voice

        .macro  dbgbit base
        .if     P_DBG
        move.l  SP_VOICE(%sp),%d7
        add.l   #ase,%d7
        move.l  SK_DBG,%d6
        bset    %d7,%d6
        move.l  %d6,SK_DBG
        .endif
        .endm

        .text

        | ------------------------------------------------------------------
        | sk_res: a0 is the input pointer (as stock leaves it at 0x4011cbae),
        | a3 the voice. d0-d7, a1, a2, a4, a5 are set by stock before use from
        | here on, so they are free.
        | ------------------------------------------------------------------
        .align  2
sk_res:
        .if     P_DBG
        tst.l   SP_VOICE(%sp)
        bne.s   0f
        clr.l   SK_DBG
0:
        .endif
        lea     V_STATE(%a3),%a1                  | the filter state: all zero?
        moveq   #12-1,%d0
1:      tst.l   (%a1)+
        bne.s   5f
        subq.l  #1,%d0
        bpl.s   1b
        move.l  V_RATE(%a3),%d5
        move.l  %d5,%d2
        moveq   #22,%d0
        asr.l   %d0,%d2                           | hi = rate asr 22
        move.l  %d5,%d3
        moveq   #10,%d0
        lsl.l   %d0,%d3                           | lo = rate << 10
        add.l   V_PHASE(%a3),%d3
        moveq   #0,%d0
        addx.l  %d0,%d2                           | the carry into hi
        tst.l   %d2
        bmi.s   7f                                | backwards: leave it to stock
        move.l  %a0,%a1                           | samples 0 .. hi+4, zero?
        move.l  %d2,%d0
        addq.l  #5,%d0
        lsr.l   #1,%d0                            | in pairs
2:      tst.l   (%a1)+
        bne.s   6f
        subq.l  #1,%d0
        bne.s   2b
        move.l  %d3,V_PHASE(%a3)                  | silence: the loop's state
        move.l  %d2,V_ADV(%a3)
        add.l   %d2,V_POS(%a3)
        moveq   #1,%d0
        move.b  %d0,sk_flag
        dbgbit  0
        jmp     RES_SKIP
5:      dbgbit  8
        bra.s   8f
6:      dbgbit  16
        bra.s   8f
7:      dbgbit  24
8:      clr.b   sk_flag
        move.l  V_RATE(%a3),%d5                   | displaced
        move.l  %d5,%d2                           | displaced
        jmp     RES_RESUME

        | ------------------------------------------------------------------
        | sk_fir: skipped voice -> the filter's output zeroed, on to the ramp.
        | The ramp sets every register it reads.
        | ------------------------------------------------------------------
        .align  2
sk_fir:
        tst.b   sk_flag
        beq.s   9f
        lea     FIR_OUT,%a0
        moveq   #0,%d0
        moveq   #34-1,%d1
1:      move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bpl.s   1b
        jmp     FIR_SKIP
9:      lea     V_STATE(%a3),%a0                  | displaced
        move.l  %a0,-(%sp)                        | displaced
        jmp     FIR_RESUME

sk_flag: .byte  0
