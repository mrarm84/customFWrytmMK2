        | Mod 0021 - new digital machines in the hidden machine slots.
        |
        | First batch, a test build: DG SINE in slot 44 (was BD TEST) and DG SAW
        | in slot 45 (was SD TEST). Both run on any voice: they leave the analog
        | circuit reset, as UT IMPULSE does, and write the voice's digital
        | waveform stream (0x80006bf8 + 128v, 32 signed 32-bit frames a block),
        | which voice_output_mix sums into the voice's channel ahead of its
        | analog filter and amp. So the track's FILTER and AMP pages shape them
        | as they shape UT NOISE.
        |
        | THE CALL. The audio interrupt (0x401211d6) calls each voice's machine
        | once a block as fn(voice, 0x800063c0, params, pitch): params the
        | track's eight SRC words (8.8) in sound index order 9..16, pitch the
        | note in semitones, 16.16, 60 << 16 for the track's own pitch. The
        | machine state is 32 bytes at 0x8000fef8 + 32v; a synth trig clears
        | words 0 and 1, a machine change without a trig sets word 0 to -1, and
        | the interrupt counts word 1 down by 16 a block while word 0 >= 0.
        | Here word 0 is 1 while running, +8 phase 1, +12 phase 2, +16 the sub's
        | phase, +20 the amplitude envelope (Q30), +24 the sweep envelope (Q30).
        |
        | TUNING. TUN is 0..127 in semitones, 64 the base; FIN -64..+63 cents.
        | The note is pitch + (TUN - 64) + FIN, A4 = note 69 = 440 Hz at 48 kHz,
        | so TUN 64 at the track's own pitch is C4, 261.63 Hz. The phase
        | increment comes from a 13-entry table of the top octave (notes
        | 120..132, exact to the rounding of a 32-bit increment), linearly
        | interpolated within the semitone (under 0.7 cents) and shifted down
        | by whole octaves (exact). Notes are held to 0..127.
        |
        | DEC. 127 holds, so the AMP page's envelope shapes the note; below it
        | the level falls exponentially, per block, from a half-life of about
        | 1.4 ms at 0 to about 30 s at 126, halving every 8 steps. SWT is the
        | same curve for the sweep.
        |
        | No EMAC: the machines run with MACSR in fractional mode and these use
        | plain muls/mulu/divu only, so the accumulators are left untouched.

        .include "symbols.inc"

        .equ    WAVE_BUF,       0x80006bf8        | + 128v, 32 longs
        .equ    NOISE_BUF,      0x80007040        | + 128v, 32 longs
        .equ    NOISE_GAIN,     0x80007000        | + 8v, 2 longs
        .equ    MSTATE,         0x8000fef8        | + 32v
        .equ    VOICE_RESET,    0x4011e456        | (voice, ctrl)
        .equ    FRAMES,         32
        .equ    ENV_FULL,       0x40000000

        | state
        .equ    ST_RUN,         0
        .equ    ST_PH1,         8
        .equ    ST_PH2,         12
        .equ    ST_PH3,         16
        .equ    ST_ENV,         20
        .equ    ST_SWE,         24
        .equ    ST_PH4,         28

        | RAM parameter records (param_info), built at boot. Stock gives some of
        | the reused test-machine ids list flags and label formatters there
        | (SD TEST's WAV and FRO: +0 0x80000, formatter 0x419a4788), which the
        | ROM record cannot undo; dg_fixram copies a plain 0..127 record over
        | each id this mod uses and sets its top from the ROM record's max.
        .equ    PARAM_INFO,     0x419a4888
        .equ    PI_STRIDE,      0x54
        .equ    PI_COPY,        0x34              | flags, range, two std::functions
        .equ    ROM_REC,        0x401bf918
        .equ    ROM_STRIDE,     0x34
        .equ    ID_TEMPLATE,    410               | a plain 0..127 record, unused by stock
        .equ    ID_SENTINEL,    420               | fixed last; differs from the template until then

        | the frame both machines keep: 11 registers saved
        .equ    A_VOICE,        48
        .equ    A_CTRL,         52
        .equ    A_PARAMS,       56
        .equ    A_PITCH,        60

        | params, by sound index: word (index - 9) * 2
        .equ    P_LEV,          0                 | 9
        .equ    P_TUN,          2                 | 10
        .equ    P_DEC,          4                 | 11
        .equ    P_FIN,          6                 | 12
        .equ    P_SWD,          8                 | 13 (SINE)
        .equ    P_SWT,          10                | 14 (SINE)
        .equ    P_DRV,          12                | 15 (SINE)
        .equ    P_DET,          12                | 15 (SAW)
        .equ    P_SUB,          14                | 16 (SAW, PULSE)
        .equ    P_PW,           8                 | 13 (PULSE)
        .equ    P_PWD,          10                | 14
        .equ    P_PWR,          12                | 15
        .equ    P_RAT,          8                 | 13 (FM2)
        .equ    P_FMA,          10                | 14
        .equ    P_FMD,          12                | 15
        .equ    P_FB,           14                | 16
        .equ    P_D16,          8                 | 13 (ORGAN)
        .equ    P_D8,           10                | 14
        .equ    P_D5,           12                | 15
        .equ    P_D4,           14                | 16

        .text
        .align  2

        | ------------------------------------------------------------ DG SINE
        | A sine, phase 0 at the trig, with a pitch sweep (SWD up to +63.5
        | semitones, falling away at SWT) and a soft-clip drive (DRV 0 off).
dg_sine:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit

        bsr.w   dg_note                           | d3 = note, 16.16
        move.l  ST_SWE(%a2),%d0                   | + sweep: env (Q15) * SWD >> 8
        asr.l   #8,%d0
        asr.l   #7,%d0
        move.w  P_SWD(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        asr.l   #8,%d0
        add.l   %d0,%d3
        move.l  ST_SWE(%a2),%d0
        move.w  P_SWT(%a3),%d1
        bsr.w   dg_decay
        move.l  %d0,ST_SWE(%a2)
        move.l  %d3,%d0
        bsr.w   dg_inc
        move.l  %d0,%d6                           | increment


        moveq   #0,%d2                            | drive gain, 0 = off
        move.w  P_DRV(%a3),%d0
        ext.l   %d0
        asr.l   #6,%d0
        ble.s   1f
        moveq   #21,%d2                           | 21/32 * 1.5 ~ unity for small signals
        add.l   %d0,%d2
1:
        move.l  ST_PH1(%a2),%d3
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
2:
        move.l  %d3,%d0
        swap    %d0
        ext.l   %d0
        bsr.w   dg_sin
        tst.l   %d2
        beq.s   3f
        bsr.w   dg_drive
3:
        move.l  %d0,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   2b
        move.l  %d3,ST_PH1(%a2)
        movea.l %d6,%a6                           | SUB (16), then the level
        bsr.w   dg_finish
        bra.w   dg_exit

        | ------------------------------------------------------------- DG SAW
        | A band-limited saw (polyBLEP), a second saw DET up to 50 cents above
        | it (DET 0 leaves one), and a sine an octave below mixed in by SUB (127
        | is half and half). Built in passes over the waveform buffer, Q15.
dg_saw:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit

        bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        movea.l %d0,%a6                           | a6 = increment 1

        | pass 1: saw 1
        move.l  %a6,%d6
        move.l  ST_PH1(%a2),%d3
        bsr.w   dg_sawpass_set
        move.l  %d3,ST_PH1(%a2)

        | pass 2: saw 2, averaged in
        move.w  P_DET(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        ble.s   5f
        move.l  %a6,%d6                           | inc2 = inc1 + inc1 * det * 15 / 2^16
        moveq   #12,%d1
        lsr.l   %d1,%d6
        muls.l  %d0,%d6
        move.l  %d6,%d0
        lsl.l   #4,%d6
        sub.l   %d0,%d6                           | * 15
        lsr.l   #4,%d6
        add.l   %a6,%d6
        move.l  ST_PH2(%a2),%d3
        bsr.w   dg_sawpass_add
        move.l  %d3,ST_PH2(%a2)
        bra.s   6f
5:
        move.l  ST_PH1(%a2),ST_PH2(%a2)           | DET 0: saw 2 follows saw 1
6:
        moveq   #8,%d1                            | DRV
        bsr.w   dg_drvpass
        moveq   #10,%d1                           | NOI
        bsr.w   dg_noipass
        bsr.w   dg_finish
        bra.w   dg_exit

        | dg_finish(a6 the increment, a4 the buffer of Q15 samples): mixes in
        | the sub (SUB, sound index 16), an octave down, then applies the
        | level. Clobbers d0..d7, a0, a1.
dg_finish:
        move.w  P_SUB(%a3),%d2
        ext.l   %d2
        ble.s   8f
        move.l  %a6,%d6
        lsr.l   #1,%d6
        move.l  ST_PH3(%a2),%d3
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
7:
        move.l  %d3,%d0
        swap    %d0
        ext.l   %d0
        bsr.w   dg_sin
        move.l  (%a0),%d1
        sub.l   %d1,%d0
        asr.l   #1,%d0
        muls.l  %d2,%d0
        asr.l   #8,%d0
        asr.l   #6,%d0
        add.l   %d1,%d0
        move.l  %d0,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.w   7b
        move.l  %d3,ST_PH3(%a2)
8:
        | pass 4: level. dg_levelpass is this pass alone, for batch 3.
dg_levelpass:
        bsr.w   dg_gain
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
9:
        move.l  (%a0),%d0
        bsr.w   dg_out
        subq.l  #1,%d7
        bne.s   9b
        rts

dg_exit:
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     44(%sp),%sp
        rts

        | ------------------------------------------------------------ helpers

        | dg_sawpass_set / _add (d3 phase, d6 increment, a4 buffer): one saw
        | over the block, stored, or averaged with what is there. d3 returns
        | the advanced phase. Clobbers d0, d1, d2, d4, d5, d7, a0, a1.
dg_sawpass_set:
        moveq   #0,%d4
        bra.s   1f
dg_sawpass_add:
        moveq   #1,%d4
1:
        bsr.s   dg_kdt
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
4:
        move.l  %d3,%d0
        bsr.w   dg_blep
        tst.l   %d4
        beq.s   5f
        add.l   (%a0),%d0
        asr.l   #1,%d0
5:
        move.l  %d0,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   4b
        rts

        | dg_kdt(d6 dt) -> d2 k, d5 dt >> k: the shift that brings dt into
        | 16 bits, for dg_blep's divide.
dg_kdt:
        moveq   #0,%d2
        move.l  %d6,%d5
1:
        cmp.l   #0xffff,%d5
        bls.s   2f
        lsr.l   #1,%d5
        addq.l  #1,%d2
        bra.s   1b
2:
        rts

        | dg_blep(d0 phase, d6 dt, d2 k, d5 dt >> k) -> d0 the saw, Q15.
        | naive 2p - 1, less the two-sample polyBLEP residual at the wrap.
        | Clobbers d1, a1.
dg_blep:
        movea.l %d0,%a1
        move.l  %d0,%d1
        swap    %d1
        and.l   #0xffff,%d1
        sub.l   #32768,%d1                        | naive
        cmp.l   %d6,%d0
        bcs.s   1f                                | p < dt: just after the wrap
        neg.l   %d0
        cmp.l   %d6,%d0
        bcs.s   2f                                | 2^32 - p < dt: just before it
        move.l  %d1,%d0
        rts
1:
        lsr.l   %d2,%d0                           | t = p / dt, Q16
        swap    %d0
        clr.w   %d0
        divu.l  %d5,%d0
        movea.l %d1,%a1
        move.l  %d0,%d1
        mulu.l  %d1,%d1
        clr.w   %d1
        swap    %d1                               | t^2
        add.l   %d0,%d0
        sub.l   %d1,%d0
        sub.l   #65536,%d0                        | 2t - t^2 - 1, -1..0
        asr.l   #1,%d0
        move.l  %a1,%d1
        sub.l   %d0,%d1
        move.l  %d1,%d0
        rts
2:
        lsr.l   %d2,%d0                           | u = (2^32 - p) / dt, Q16
        swap    %d0
        clr.w   %d0
        divu.l  %d5,%d0
        movea.l %d1,%a1
        move.l  #65536,%d1
        sub.l   %d0,%d1                           | 1 - u
        cmp.l   #65535,%d1
        bls.s   3f
        move.l  #65535,%d1
3:
        mulu.l  %d1,%d1
        clr.w   %d1
        swap    %d1                               | (1 - u)^2, 0..1
        lsr.l   #1,%d1
        move.l  %a1,%d0
        sub.l   %d1,%d0
        rts

        | dg_enter(d7 voice, a5 ctrl) -> a2 state, a4 waveform buffer,
        | d0 = 0 when silent (no trig since the machine was set). Clears the
        | voice's noise buffer and gains every block; on a trig resets the
        | circuit and the state. Clobbers d0, d1, a0, a1.
dg_enter:
        bsr.w   dg_fixram
        move.l  %d7,%d0
        lsl.l   #5,%d0
        add.l   #MSTATE,%d0
        movea.l %d0,%a2
        move.l  %d7,%d0
        moveq   #7,%d1
        lsl.l   %d1,%d0
        movea.l %d0,%a4
        movea.l %d0,%a0
        adda.l  #NOISE_BUF,%a0
        adda.l  #WAVE_BUF,%a4
        moveq   #FRAMES,%d1
1:
        clr.l   (%a0)+
        subq.l  #1,%d1
        bne.s   1b
        move.l  %d7,%d0
        lsl.l   #3,%d0
        add.l   #NOISE_GAIN,%d0
        movea.l %d0,%a0
        clr.l   (%a0)+
        clr.l   (%a0)

        move.l  ST_RUN(%a2),%d0
        bmi.s   3f
        bne.s   2f
        move.l  %a5,-(%sp)                        | a trig
        move.l  %d7,-(%sp)
        jsr     VOICE_RESET
        addq.l  #8,%sp
        moveq   #1,%d0
        move.l  %d0,ST_RUN(%a2)
        clr.l   ST_PH1(%a2)
        clr.l   ST_PH2(%a2)
        clr.l   ST_PH3(%a2)
        clr.l   ST_PH4(%a2)
        move.l  #ENV_FULL,%d0
        move.l  %d0,ST_ENV(%a2)
        move.l  %d0,ST_SWE(%a2)
2:
        move.l  #ENV_FULL,%d1                     | envelopes held to 0..1, so a
        cmp.l   ST_ENV(%a2),%d1                   | state another path left can
        bcc.s   5f                                | never overflow the gain
        move.l  %d1,ST_ENV(%a2)
5:
        cmp.l   ST_SWE(%a2),%d1
        bcc.s   6f
        move.l  %d1,ST_SWE(%a2)
6:
        moveq   #1,%d0
        rts
3:
        movea.l %a4,%a0
        moveq   #FRAMES,%d1
4:
        clr.l   (%a0)+
        subq.l  #1,%d1
        bne.s   4b
        moveq   #0,%d0
        rts

        | dg_note -> d3 the note, semitones 16.16: pitch + (TUN - 64) + FIN
        | cents. Clobbers d0.
dg_note:
        move.l  A_PITCH+4(%sp),%d3
        move.w  P_TUN(%a3),%d0
        ext.l   %d0
        sub.l   #0x4000,%d0
        lsl.l   #8,%d0
        add.l   %d0,%d3
        move.w  P_FIN(%a3),%d0
        ext.l   %d0
        sub.l   #0x4000,%d0
        muls.w  #655,%d0                          | 8.8 cents -> 1/65536 semitone << 8
        asr.l   #8,%d0
        add.l   %d0,%d3
        rts

        | dg_inc(d0 note 16.16) -> d0 the phase increment at 48 kHz.
        | Clobbers d1, a1.
dg_inc:
        move.l  %d2,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %d0,%d1
        swap    %d1
        ext.l   %d1                               | n
        and.l   #0xffff,%d0                       | fraction
        tst.l   %d1
        bge.s   1f
        moveq   #0,%d1
        moveq   #0,%d0
1:
        moveq   #127,%d2
        cmp.l   %d2,%d1
        ble.s   2f
        move.l  %d2,%d1
        moveq   #0,%d0
2:
        moveq   #0,%d2                            | octaves below the table
        sub.l   #120,%d1
3:
        tst.l   %d1
        bge.s   4f
        moveq   #12,%d3
        add.l   %d3,%d1
        addq.l  #1,%d2
        bra.s   3b
4:
        lea     inc_tab(%pc),%a1
        lsl.l   #2,%d1
        move.l  (%a1,%d1.l),%d3
        move.l  4(%a1,%d1.l),%d1
        sub.l   %d3,%d1
        lsr.l   #8,%d1
        lsr.l   #8,%d0
        muls.l  %d0,%d1
        add.l   %d3,%d1
        lsr.l   %d2,%d1
        move.l  %d1,%d0
        move.l  (%sp)+,%d3
        move.l  (%sp)+,%d2
        rts

        | dg_decay(d0 envelope, d1.w the knob, 8.8) -> d0. 127 holds; below
        | it env -= env * r / 2^16, r = 2^15 >> (d / 8), less r * (d % 8) / 16.
        | Clobbers d1.
dg_decay:
        ext.l   %d1
        cmp.l   #0x7eff,%d1
        bgt.s   9f
        asr.l   #8,%d1
        bge.s   1f
        moveq   #0,%d1
1:
        move.l  %d2,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %d1,%d2
        lsr.l   #3,%d2
        moveq   #7,%d3
        and.l   %d3,%d1
        move.l  #0x8000,%d3
        lsr.l   %d2,%d3                           | r
        move.l  %d3,%d2
        muls.l  %d1,%d2
        asr.l   #4,%d2
        sub.l   %d2,%d3
        move.l  %d0,%d1
        swap    %d1
        and.l   #0xffff,%d1
        muls.l  %d3,%d1
        sub.l   %d1,%d0
        cmp.l   #0x10000,%d0
        bcc.s   2f
        moveq   #0,%d0
2:
        move.l  (%sp)+,%d3
        move.l  (%sp)+,%d2
9:
        rts

        | dg_gain -> d4 the block's starting gain, d5 its step a frame (Q30):
        | the envelope times LEV^2, the envelope advanced by DEC. Clobbers
        | d0, d1, d2.
dg_gain:
        move.l  ST_ENV(%a2),%d4
        move.l  %d4,%d0
        move.w  P_DEC(%a3),%d1
        bsr.w   dg_ampdec
        move.l  %d0,ST_ENV(%a2)
        move.w  P_LEV(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d1
        moveq   #15,%d2
        asr.l   %d2,%d1                           | LEV^2, Q15
        asr.l   %d2,%d4
        muls.l  %d1,%d4                           | gain at the block's start
        asr.l   %d2,%d0
        muls.l  %d1,%d0
        sub.l   %d4,%d0
        asr.l   #5,%d0
        move.l  %d0,%d5
        rts

        | dg_out(d0 sample Q15, a0 out, d4 gain, d5 step): clamp, scale,
        | store, advance. Clobbers d0, d1.
dg_out:
        cmp.l   #32767,%d0
        ble.s   1f
        move.l  #32767,%d0
1:
        cmp.l   #-32767,%d0
        bge.s   2f
        move.l  #-32767,%d0
2:
        move.l  %d4,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        muls.l  %d1,%d0
        add.l   %d0,%d0
        move.l  %d0,(%a0)+
        add.l   %d5,%d4
        rts

        | dg_sin(d0 x, -32768..32767 for -pi..pi) -> d0 sin, Q15. The
        | parabola 4x(1 - |x|) refined by 0.225 (y|y| - y): within 0.1%.
        | Clobbers d1.
dg_sin:
        move.l  %d0,%d1
        bpl.s   1f
        neg.l   %d1
1:
        neg.l   %d1
        add.l   #32768,%d1
        muls.l  %d1,%d0
        moveq   #13,%d1
        asr.l   %d1,%d0                           | y, -32768..32768
        move.l  %d0,%d1
        bpl.s   2f
        neg.l   %d1
2:
        muls.l  %d0,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1                            | y |y|
        sub.l   %d0,%d1
        muls.w  #7373,%d1                         | 0.225, Q15
        asr.l   #8,%d1
        asr.l   #7,%d1
        add.l   %d1,%d0
        cmp.l   #32767,%d0
        ble.s   3f
        move.l  #32767,%d0
3:
        cmp.l   #-32767,%d0
        bge.s   4f
        move.l  #-32767,%d0
4:
        rts

        | dg_drive(d0 y Q15, d2 gain / 32) -> d0: u = clamp(y g), then
        | 1.5u - 0.5u^3. Clobbers d1.
dg_drive:
        muls.l  %d2,%d0
        asr.l   #5,%d0
        cmp.l   #32767,%d0
        ble.s   1f
        move.l  #32767,%d0
1:
        cmp.l   #-32767,%d0
        bge.s   2f
        move.l  #-32767,%d0
2:
        move.l  %d0,%d1
        muls.l  %d1,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        muls.l  %d0,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1                            | u^3
        neg.l   %d1
        add.l   %d0,%d1
        add.l   %d0,%d1
        add.l   %d0,%d1
        asr.l   #1,%d1
        move.l  %d1,%d0
        rts

        .align  2
        | phase increments at 48 kHz for notes 120..132 (A4 = 440 Hz)
inc_tab:
        .long   749115498, 793660223, 840853716, 890853480
        .long   943826385, 999949222, 1059409297, 1122405052
        .long   1189146729, 1259857073, 1334772074, 1414141751
        .long   1498230996

        | names
txt_sine_long:  .asciz  "DG SINE"
txt_sine_short: .asciz  "DSIN"
txt_saw_long:   .asciz  "DG SAW"
txt_saw_short:  .asciz  "DSAW"
txt_lev_l:      .asciz  "Level"
txt_lev_s:      .asciz  "LEV"
txt_tun_l:      .asciz  "Tune"
txt_tun_s:      .asciz  "TUN"
txt_dec_l:      .asciz  "Decay"
txt_dec_s:      .asciz  "DEC"
txt_fin_l:      .asciz  "Fine Tune"
txt_fin_s:      .asciz  "FIN"
txt_swd_l:      .asciz  "Sweep Depth"
txt_swd_s:      .asciz  "SWD"
txt_swt_l:      .asciz  "Sweep Time"
txt_swt_s:      .asciz  "SWT"
txt_drv_l:      .asciz  "Drive"
txt_drv_s:      .asciz  "DRV"
txt_det_l:      .asciz  "Detune"
txt_det_s:      .asciz  "DET"
txt_sub_l:      .asciz  "Sub Osc"
txt_sub_s:      .asciz  "SUB"
        .align  2

        | ==================================================================
        | cave26 (the MT and BT TEST routines): batch 2 and the RAM fix.
        | ==================================================================
        .section .text2,"ax"
        .align  2

        | ----------------------------------------------------------- DG PULSE
        | A band-limited pulse, the difference of two polyBLEP saws PW apart
        | (so it has no DC at any width), PW 64 square. PWD sweeps the width
        | with a triangle at PWR (about 0.008 Hz at 0, 12 Hz at 127, an octave
        | every 12 steps); SUB as DG SAW's.
dg_pulse:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit

        bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        movea.l %d0,%a6                           | the increment

        move.w  P_PWR(%a3),%d0                    | the PWM triangle, a block a step
        ext.l   %d0
        lsl.l   #8,%d0
        bsr.w   dg_inc
        lsr.l   #5,%d0
        add.l   ST_PH2(%a2),%d0
        move.l  %d0,ST_PH2(%a2)
        swap    %d0
        and.l   #0xffff,%d0
        sub.l   #32768,%d0
        bpl.s   1f
        neg.l   %d0
1:
        add.l   %d0,%d0
        sub.l   #32768,%d0                        | -1..1, Q15
        move.w  P_PWD(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        asr.l   #8,%d0
        asr.l   #7,%d0
        moveq   #15,%d1
        lsl.l   %d1,%d0                           | up to +-0.5, Q31
        move.w  P_PW(%a3),%d1
        ext.l   %d1
        swap    %d1
        clr.w   %d1                               | PW / 128, Q31
        add.l   %d1,%d0
        cmp.l   #0x02000000,%d0
        bge.s   2f
        move.l  #0x02000000,%d0
2:
        cmp.l   #0x7e000000,%d0
        ble.s   3f
        move.l  #0x7e000000,%d0
3:
        add.l   %d0,%d0
        movea.l %d0,%a5                           | width, Q32

        move.l  %a6,%d6
        bsr.w   dg_kdt
        move.l  ST_PH1(%a2),%d3
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
4:
        move.l  %d3,%d0
        bsr.w   dg_blep
        move.l  %d0,%d4
        move.l  %d3,%d0
        add.l   %a5,%d0
        bsr.w   dg_blep
        sub.l   %d0,%d4
        asr.l   #1,%d4
        move.l  %d4,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   4b
        move.l  %d3,ST_PH1(%a2)
        bsr.w   dg_finish
        bra.w   dg_exit

        | ------------------------------------------------------------- DG FM2
        | Two-operator FM: a sine carrier at the note, phase-modulated by a sine
        | modulator at RAT's ratio (0..15: 1/2 1 3/2 2 5/2 3 7/2 4 5 6 7 8 9 10
        | 12 16), index FMA up to about 2 pi, falling away at FMD (127 holds);
        | FB the modulator's own feedback.
dg_fm2:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit

        bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        move.l  %d0,%d6                           | carrier increment
        move.w  P_RAT(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        bge.s   1f
        moveq   #0,%d0
1:
        moveq   #15,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:
        lea     fm_ratio,%a1
        add.l   %d0,%d0
        mvz.w   (%a1,%d0.l),%d0                   | ratio, Q8
        move.l  %d6,%d1
        lsr.l   #8,%d1
        mulu.l  %d0,%d1                           | modulo 2^32, as a phase is
        movea.l %d1,%a6                           | modulator increment

        move.l  ST_SWE(%a2),%d0                   | the index envelope
        move.w  P_FMD(%a3),%d1
        bsr.w   dg_decay
        move.l  %d0,ST_SWE(%a2)
        moveq   #15,%d1
        asr.l   %d1,%d0
        move.w  P_FMA(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        moveq   #15,%d1
        asr.l   %d1,%d0
        movea.l %d0,%a5                           | index, up to 32512

        bsr.w   dg_gain
        move.l  ST_PH1(%a2),%d3                   | carrier phase
        move.l  ST_PH2(%a2),%d2                   | modulator phase
        movea.l ST_PH3(%a2),%a1                   | the modulator's last output
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
3:
        move.l  %a1,%d0
        move.w  P_FB(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        swap    %d0
        ext.l   %d0                               | feedback, up to pi / 2
        move.l  %d2,%d1
        swap    %d1
        ext.l   %d1
        add.l   %d1,%d0
        ext.l   %d0
        bsr.w   dg_sin
        movea.l %d0,%a1
        move.l  %a5,%d1
        muls.l  %d1,%d0
        asr.l   #8,%d0
        asr.l   #6,%d0                            | phase offset, up to 2 pi
        move.l  %d3,%d1
        swap    %d1
        ext.l   %d1
        add.l   %d1,%d0
        ext.l   %d0
        bsr.w   dg_sin
        bsr.w   dg_out
        add.l   %a6,%d2
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   3b
        move.l  %d3,ST_PH1(%a2)
        move.l  %d2,ST_PH2(%a2)
        move.l  %a1,ST_PH3(%a2)
        bra.w   dg_exit

        | The rest of the batch goes back to cave25, after batch 1.
        .text
        .align  2

        | ----------------------------------------------------------- DG ORGAN
        | Four drawbars, sines at 16 ft (an octave down), 8 ft (the note),
        | 5 1/3 ft (a fifth above) and 4 ft (an octave up), D16 D8 D5 D4 their
        | levels; the sum is halved, so two full drawbars reach full scale.
dg_organ:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit

        bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        move.l  %d0,%d6                           | 8 ft
        bsr.w   dg_gain
        move.l  ST_PH1(%a2),%d2                   | 8 ft
        move.l  ST_PH2(%a2),%d3                   | 16 ft
        movea.l ST_PH3(%a2),%a1                   | 5 1/3 ft
        movea.l ST_PH4(%a2),%a5                   | 4 ft
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
1:
        move.l  %d3,%d0
        swap    %d0
        ext.l   %d0
        bsr.w   dg_sin
        move.w  P_D16(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        asr.l   #2,%d0
        movea.l %d0,%a6
        move.l  %d2,%d0
        swap    %d0
        ext.l   %d0
        bsr.w   dg_sin
        move.w  P_D8(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        asr.l   #2,%d0
        adda.l  %d0,%a6
        move.l  %a1,%d0
        swap    %d0
        ext.l   %d0
        bsr.w   dg_sin
        move.w  P_D5(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        asr.l   #2,%d0
        adda.l  %d0,%a6
        move.l  %a5,%d0
        swap    %d0
        ext.l   %d0
        bsr.w   dg_sin
        move.w  P_D4(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d0
        asr.l   #2,%d0
        adda.l  %d0,%a6
        move.l  %a6,%d0
        moveq   #14,%d1
        asr.l   %d1,%d0                           | half the sum, Q15
        bsr.w   dg_out
        add.l   %d6,%d2
        move.l  %d6,%d0
        lsr.l   #1,%d0
        add.l   %d0,%d3
        add.l   %d6,%d0
        adda.l  %d0,%a1
        move.l  %d6,%d0
        add.l   %d0,%d0
        adda.l  %d0,%a5
        subq.l  #1,%d7
        bne.w   1b
        move.l  %d2,ST_PH1(%a2)
        move.l  %d3,ST_PH2(%a2)
        move.l  %a1,ST_PH3(%a2)
        move.l  %a5,ST_PH4(%a2)
        bra.w   dg_exit

        | ------------------------------------------------------------ dg_fixram
        | Once after boot: the RAM records of every id these machines use take
        | the template's flags, range and formatters, and their top from the
        | ROM record's max. Done when the sentinel matches the template.
        | Clobbers d0, d1, a0, a1.
dg_fixram:
        lea     PARAM_INFO+ID_TEMPLATE*PI_STRIDE,%a0
        lea     PARAM_INFO+ID_SENTINEL*PI_STRIDE,%a1
        move.l  (%a0),%d0
        cmp.l   (%a1),%d0
        bne.s   1f
        move.l  0x20(%a0),%d0
        cmp.l   0x20(%a1),%d0
        bne.s   1f
        rts
1:
        move.l  %d2,-(%sp)
        move.l  %a2,-(%sp)
        lea     fix_ids,%a2
2:
        mvz.w   (%a2)+,%d0
        tst.l   %d0
        beq.s   4f
        move.l  %d0,%d1
        moveq   #PI_STRIDE,%d2
        mulu.l  %d2,%d0
        add.l   #PARAM_INFO,%d0
        movea.l %d0,%a1
        lea     PARAM_INFO+ID_TEMPLATE*PI_STRIDE,%a0
        moveq   #PI_COPY/4,%d2
3:
        move.l  (%a0)+,(%a1)+
        subq.l  #1,%d2
        bne.s   3b
        moveq   #ROM_STRIDE,%d2
        mulu.l  %d2,%d1
        add.l   #ROM_REC+0xc,%d1
        movea.l %d1,%a0
        movea.l %d0,%a1
        move.l  (%a0),8(%a1)                      | the top, the ROM max
        bra.s   2b
4:
        movea.l (%sp)+,%a2
        move.l  (%sp)+,%d2
        rts

        .align  2
fm_ratio:
        .word   128, 256, 384, 512, 640, 768, 896, 1024
        .word   1280, 1536, 1792, 2048, 2304, 2560, 3072, 4096


txt_pulse_long: .asciz  "DG PULSE"
txt_pulse_short: .asciz "DPLS"
txt_fm2_long:   .asciz  "DG FM2"
txt_fm2_short:  .asciz  "DFM2"
txt_organ_long: .asciz  "DG ORGAN"
txt_organ_short: .asciz "DORG"
txt_pw_l:       .asciz  "Pulse Width"
txt_pw_s:       .asciz  "PW"
txt_pwd_l:      .asciz  "PWM Depth"
txt_pwd_s:      .asciz  "PWD"
txt_pwr_l:      .asciz  "PWM Rate"
txt_pwr_s:      .asciz  "PWR"
txt_rat_l:      .asciz  "Ratio"
txt_rat_s:      .asciz  "RAT"
txt_fma_l:      .asciz  "FM Amount"
txt_fma_s:      .asciz  "FMA"
txt_fmd_l:      .asciz  "FM Decay"
txt_fmd_s:      .asciz  "FMD"
txt_fb_l:       .asciz  "Feedback"
txt_fb_s:       .asciz  "FB"
txt_d16_l:      .asciz  "Drawbar 16"
txt_d16_s:      .asciz  "D16"
txt_d8_l:       .asciz  "Drawbar 8"
txt_d8_s:       .asciz  "D8"
txt_d5_l:       .asciz  "Drawbar 5 1/3"
txt_d5_s:       .asciz  "D5"
txt_d4_l:       .asciz  "Drawbar 4"
txt_d4_s:       .asciz  "D4"
        .align  2

        | ==================================================================
        | Batch 3: DG CHORD (49, was MT TEST), DG SUPER (51, CY TEST), DG
        | PLUCK (52, CB TEST). The code takes the BD TEST and BT IMPROVED
        | routines (.text3, .text5, near the helpers) and the HH TEST routine
        | (.text6, tables and names; HH TEST's entry points at DISABLE). The
        | records are the free test ones (415, 449..455; 0013 and 0019 hold
        | 446 and 456..460) and BT IMPROVED's and FUNC GEN's (398..407); both
        | machines stay hidden, and BT IMPROVED's entry points at DISABLE.
        | Per-voice state past the 32 bytes, and DG PLUCK's strings, live in
        | the SDRAM 0022 freed, which the delay's start-up clear zeroes.
        | ==================================================================
        .equ    EXT_STATE,      0x4B600000        | + 256v
        .equ    PLK_BUF,        0x4B610000        | + 16 KB v, 4096 longs
        .equ    PLK_MASK,       0xfff
        .equ    PLK_MAXP,       4000              | longest period, samples (12 Hz)
        .equ    P_CHD,          8                 | 13 (CHORD)
        .equ    P_INV,          10                | 14
        .equ    P_CDT,          12                | 15
        .equ    P_SDT,          8                 | 13 (SUPER)
        .equ    P_MIX,          10                | 14
        .equ    P_BRT,          8                 | 13 (PLUCK)
        .equ    P_PIK,          10                | 14
        .equ    P_LEN,          12                | 15
        .equ    PLK_HIST,       0x4B630000        | + 16 KB v: the pluck, for PIK

        .section .text3,"ax"
        .align  2

        | ----------------------------------------------------------- DG CHORD
        | Four polyBLEP saws on a chord from CHD's table (16 chords), the
        | lowest INV notes raised an octave, DET spreading them up to about
        | 12 cents. Each saw at a quarter, so the four never clip.
dg_chord:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit
        tst.l   ST_PH1(%a2)
        bne.s   1f
        moveq   #1,%d0                            | the trig: the four saws
        move.l  %d0,ST_PH1(%a2)                   | start spread apart
        move.l  #0x55555555,%d0
        move.l  %d0,ST_PH2(%a2)
        add.l   %d0,%d0
        move.l  %d0,ST_PH3(%a2)
        lsr.l   #2,%d0
        move.l  %d0,ST_PH4(%a2)
1:
        bsr.w   dg_note                           | d3 the root
        bsr.w   dg_clrbuf
        move.w  P_CHD(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        bge.s   2f
        moveq   #0,%d0
2:      moveq   #15,%d1
        cmp.l   %d1,%d0
        ble.s   3f
        move.l  %d1,%d0
3:      lsl.l   #2,%d0
        lea     chord_tab,%a0
        adda.l  %d0,%a0                           | the chord's four notes
        move.w  P_INV(%a3),%d4
        ext.l   %d4
        asr.l   #8,%d4                            | notes below INV up an octave
        move.w  P_CDT(%a3),%d2
        ext.l   %d2
        asr.l   #2,%d2                            | DET * 64, 1/65536 semitone
        lea     -16(%sp),%sp                      | the four increments
        moveq   #0,%d5
4:      move.b  (%a0,%d5.l),%d0
        extb.l  %d0
        cmp.l   %d4,%d5
        bge.s   5f
        moveq   #12,%d1
        add.l   %d1,%d0
5:      swap    %d0
        clr.w   %d0
        add.l   %d3,%d0
        lea     chord_det,%a1
        move.b  (%a1,%d5.l),%d1
        extb.l  %d1
        muls.l  %d2,%d1
        add.l   %d1,%d0
        bsr.w   dg_inc
        move.l  %d0,(%sp,%d5.l*4)
        addq.l  #1,%d5
        moveq   #4,%d0
        cmp.l   %d0,%d5
        blt.s   4b

        suba.l  %a5,%a5
6:      move.l  %a5,%d0
        move.l  (%sp,%d0.l*4),%d6
        lea     chord_st,%a1
        mvz.b   (%a1,%d0.l),%d1
        move.l  (%a2,%d1.l),%d3
        move.l  #0x2000,%d4
        bsr.w   dg_sawacc
        move.l  %a5,%d0
        lea     chord_st,%a1
        mvz.b   (%a1,%d0.l),%d1
        move.l  %d3,(%a2,%d1.l)
        addq.l  #1,%a5
        moveq   #4,%d0
        cmpa.l  %d0,%a5
        blt.s   6b
        lea     16(%sp),%sp
        moveq   #14,%d1                           | DRV
        bsr.w   dg_drvpass
        bsr.w   dg_levelpass
        bra.w   dg_exit

        | plk_excite(a3 params, a4 the block, a5 the string, a6 the pluck's
        | state): the block's share of the pluck, BRT-low-passed differenced
        | noise less its PIK comb, or zeros. Clobbers d0..d3, d6, d7, a0, a1.
plk_excite:
        bsr.w   dg_clrbuf                         | the excitation, into the block
        move.l  4(%a6),%d7
        beq.w   8f
        moveq   #FRAMES,%d0
        cmp.l   %d0,%d7
        bls.s   6f
        move.l  %d0,%d7
6:      sub.l   %d7,4(%a6)
        move.w  P_BRT(%a3),%d3                    | its low-pass, 1/8 .. 1
        ext.l   %d3
        mulu.w  #7,%d3
        lsr.l   #3,%d3
        add.l   #4096,%d3
        move.l  8(%a6),%d2                        | seed
        movea.l %a4,%a0
        movea.l %a5,%a1
        adda.l  #PLK_HIST-PLK_BUF,%a1             | the pluck so far, for the comb
7:      move.l  #1664525,%d0
        mulu.l  %d0,%d2
        add.l   #1013904223,%d2
        move.l  %d2,%d0
        moveq   #17,%d1
        asr.l   %d1,%d0                           | noise, +-16384
        move.l  %d0,%d1
        sub.l   12(%a6),%d0                       | differenced: no DC
        move.l  %d1,12(%a6)
        move.l  16(%a6),%d1
        sub.l   %d1,%d0
        muls.l  %d3,%d0
        moveq   #15,%d6
        asr.l   %d6,%d0
        add.l   %d1,%d0
        move.l  %d0,16(%a6)
        move.l  20(%a6),%d6                       | PIK: less the pluck d ago, a
        move.l  %d6,%d1                           | comb, as picking along a string
        and.l   #PLK_MASK,%d1
        move.l  %d0,(%a1,%d1.l*4)
        move.l  24(%a6),%d1
        beq.s   71f
        cmp.l   %d1,%d6
        bcs.s   71f
        neg.l   %d1
        add.l   %d6,%d1
        and.l   #PLK_MASK,%d1
        sub.l   (%a1,%d1.l*4),%d0
71:     addq.l  #1,%d6
        move.l  %d6,20(%a6)
        lsl.l   #2,%d0                            | four times: the pluck's level
        move.l  %d0,(%a0)+
        subq.l  #1,%d7
        bne.w   7b
        move.l  %d2,8(%a6)
8:      rts

        | dg_clrbuf(a4): zeroes the block. Clobbers d0, a0.
dg_clrbuf:
        movea.l %a4,%a0
        moveq   #FRAMES,%d0
1:      clr.l   (%a0)+
        subq.l  #1,%d0
        bne.s   1b
        rts

        | dg_sawacc(d3 phase, d6 increment, d4 gain Q15, a4 the block): adds a
        | polyBLEP saw times the gain; d3 returns advanced. Clobbers d0, d1,
        | d2, d5, d7, a0, a1.
dg_sawacc:
        bsr.w   dg_kdt
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
1:      move.l  %d3,%d0
        bsr.w   dg_blep
        muls.l  %d4,%d0
        asr.l   #8,%d0
        asr.l   #7,%d0
        add.l   %d0,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   1b
        rts

        | ----------------------------------------------------------- DG SUPER
        | Seven polyBLEP saws, the outer six detuned by DET (squared, up to
        | about +-1.9 semitones at the edges, the JP-8000's spacing), MIX
        | raising the six and lowering the centre. Phases free-run from a
        | spread seed at the trig, in the voice's SDRAM state.
dg_super:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit
        move.l  %d7,%d0
        lsl.l   #8,%d0
        add.l   #EXT_STATE,%d0
        movea.l %d0,%a6                           | the seven phases
        tst.l   ST_PH1(%a2)
        bne.s   2f
        moveq   #1,%d0
        move.l  %d0,ST_PH1(%a2)                   | the trig, marked
        lea     super_seed,%a0
        movea.l %a6,%a1
        moveq   #7,%d1
1:      move.l  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bne.s   1b
2:
        bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        move.l  %d0,ST_PH2(%a2)                   | the centre's increment
        bsr.w   dg_clrbuf
        suba.l  %a5,%a5
3:      move.w  P_SDT(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        muls.l  %d0,%d0
        add.l   %d0,%d0                           | DET^2, Q15
        move.l  %a5,%d1
        add.l   %d1,%d1
        lea     super_k,%a0
        mvs.w   (%a0,%d1.l),%d1                   | the saw's spacing, Q16
        muls.l  %d1,%d0
        moveq   #15,%d1
        asr.l   %d1,%d0                           | its ratio offset, Q16
        move.l  ST_PH2(%a2),%d6
        move.l  %d6,%d1
        clr.w   %d1
        swap    %d1
        muls.l  %d1,%d0
        add.l   %d0,%d6                           | inc * (1 + offset)
        move.w  P_MIX(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        moveq   #3,%d1
        cmpa.l  %d1,%a5
        bne.s   4f
        moveq   #48,%d4                           | centre: 0.5 less MIX * 48
        muls.l  %d0,%d4
        neg.l   %d4
        add.l   #16384,%d4
        bra.s   5f
4:      move.l  %d0,%d4                           | sides: MIX * 32
        lsl.l   #5,%d4
5:      move.l  %a5,%d0
        move.l  (%a6,%d0.l*4),%d3
        bsr.w   dg_sawacc
        move.l  %a5,%d0
        move.l  %d3,(%a6,%d0.l*4)
        addq.l  #1,%a5
        moveq   #7,%d0
        cmpa.l  %d0,%a5
        blt.w   3b
        moveq   #12,%d1                           | DRV
        bsr.w   dg_drvpass
        movea.l ST_PH2(%a2),%a6                   | SUB, under the centre saw
        bsr.w   dg_finish
        bra.w   dg_exit

        .section .text5,"ax"
        .align  2

        | ----------------------------------------------------------- DG PLUCK
        | A plucked string (Karplus-Strong): a period of filtered noise into a
        | delay line of the note's period, which recirculates through a
        | linear-phase 3-tap low-pass (BRT: 127 none, 0 [1/4 1/2 1/4]) read
        | between samples, so the loop is the period to within a cent; DEC
        | the loss a period, set for a time constant from 1.3 ms (0) to about
        | a minute (127), pitch-independent. The level is LEV alone.
dg_pluck:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit
        move.l  %d7,%d0
        lsl.l   #8,%d0
        add.l   #EXT_STATE,%d0
        movea.l %d0,%a6                           | +0 w, +4 to excite, +8 seed,
        move.l  %d7,%d0                           | +12 last noise, +16 its low-pass
        moveq   #14,%d1
        lsl.l   %d1,%d0
        add.l   #PLK_BUF,%d0
        movea.l %d0,%a5                           | the string
        bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        tst.l   %d0
        bne.s   1f
        moveq   #1,%d0
1:      moveq   #-1,%d2                           | the period, 2^32 / inc, 16.16
        divu.l  %d0,%d2
        cmp.l   #PLK_MAXP,%d2
        bcs.s   2f
        move.l  #PLK_MAXP<<16,%d4
        bra.s   4f
2:      move.l  %d2,%d1
        mulu.l  %d0,%d1
        moveq   #-1,%d4
        sub.l   %d1,%d4                           | the remainder
        move.l  %d0,%d1
3:      cmp.l   #0xffff,%d1
        bls.s   31f
        lsr.l   #1,%d1
        lsr.l   #1,%d4
        bra.s   3b
31:     swap    %d4
        clr.w   %d4
        divu.l  %d1,%d4
        cmp.l   #0xffff,%d4
        bls.s   32f
        move.l  #0xffff,%d4
32:     swap    %d2
        clr.w   %d2
        or.l    %d2,%d4
        cmp.l   #3<<16,%d4
        bcc.s   4f
        move.l  #3<<16,%d4
4:                                                | d4 = P, 16.16
        move.w  P_DEC(%a3),%d0                    | the loss a period
        ext.l   %d0
        asr.l   #8,%d0
        bge.s   41f
        moveq   #0,%d0
41:     moveq   #1,%d1
        cmp.l   #127,%d0
        bge.s   43f
        move.l  %d0,%d2
        lsr.l   #3,%d2
        moveq   #7,%d3
        and.l   %d3,%d0
        move.l  #0x8000,%d1
        lsr.l   %d2,%d1                           | r, as dg_decay's
        move.l  %d1,%d2
        mulu.l  %d0,%d2
        lsr.l   #4,%d2
        sub.l   %d2,%d1
        bne.s   43f
        moveq   #1,%d1
43:     move.l  %d4,%d0
        moveq   #12,%d2
        lsr.l   %d2,%d0
        mulu.l  %d1,%d0
        moveq   #9,%d2
        lsr.l   %d2,%d0                           | P r / 32, Q16
        cmp.l   #0x8000,%d0
        bls.s   44f
        move.l  #0x8000,%d0
44:     move.l  %d0,-(%sp)                        | 8(sp): the loss
        move.w  P_BRT(%a3),%d0
        ext.l   %d0
        move.l  #0x7f00,%d1
        sub.l   %d0,%d1                           | b, Q15
        move.l  %d1,%d0
        asr.l   #1,%d0
        neg.l   %d0
        add.l   #32768,%d0
        move.l  %d0,-(%sp)                        | 4(sp): cm = 1 - b/2
        asr.l   #2,%d1
        move.l  %d1,-(%sp)                        | (sp): cs = b/4

        move.l  %d4,%d5
        clr.w   %d5
        swap    %d5                               | n
        and.l   #0xffff,%d4
        lsr.l   #1,%d4                            | the fraction, Q15

        tst.l   ST_PH1(%a2)                       | the trig: excite LEN's share
        bne.s   5f                                | of a period
        moveq   #1,%d0
        move.l  %d0,ST_PH1(%a2)
        move.w  P_LEN(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        addq.l  #8,%d0
        mulu.l  %d5,%d0
        moveq   #72,%d1
        divu.l  %d1,%d0                           | n (LEN + 8) / 72: LEN 64 one period
        bne.s   51f
        moveq   #1,%d0
51:     move.l  %d0,4(%a6)
        clr.l   16(%a6)
        clr.l   20(%a6)                           | the pick comb's count
5:
        move.w  P_PIK(%a3),%d0                    | the pick comb's delay, up to
        ext.l   %d0                               | half a period
        mulu.l  %d5,%d0
        clr.w   %d0
        swap    %d0
        move.l  %d0,24(%a6)
        bsr.w   plk_excite
        move.l  (%a6),%d6                         | w
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
9:      move.l  %d6,%d0
        sub.l   %d5,%d0                           | k = w - n
        move.l  %d0,%d1
        addq.l  #1,%d1
        and.l   #PLK_MASK,%d1
        move.l  (%a5,%d1.l*4),%d2                 | x[k+1]
        subq.l  #1,%d1
        and.l   #PLK_MASK,%d1
        move.l  (%a5,%d1.l*4),%d3                 | x[k]
        subq.l  #1,%d1
        and.l   #PLK_MASK,%d1
        move.l  (%a5,%d1.l*4),%d0                 | x[k-1]
        movea.l %d0,%a1
        add.l   %d0,%d2
        muls.l  (%sp),%d2
        move.l  %d3,%d0
        muls.l  4(%sp),%d0
        add.l   %d0,%d2                           | f[k], Q30
        subq.l  #1,%d1
        and.l   #PLK_MASK,%d1
        add.l   (%a5,%d1.l*4),%d3                 | x[k] + x[k-2]
        muls.l  (%sp),%d3
        move.l  %a1,%d0
        muls.l  4(%sp),%d0
        add.l   %d0,%d3                           | f[k-1], Q30
        moveq   #15,%d1
        asr.l   %d1,%d2
        asr.l   %d1,%d3
        sub.l   %d2,%d3
        muls.l  %d4,%d3
        asr.l   %d1,%d3
        add.l   %d3,%d2                           | y, between them
        move.l  %d2,%d0
        muls.l  8(%sp),%d0
        asr.l   #8,%d0
        asr.l   #8,%d0
        sub.l   %d0,%d2                           | less the loss
        add.l   (%a0),%d2                         | plus the excitation
        cmp.l   #32767,%d2
        ble.s   10f
        move.l  #32767,%d2
10:     cmp.l   #-32767,%d2
        bge.s   11f
        move.l  #-32767,%d2
11:     move.l  %d2,(%a5,%d6.l*4)
        move.l  %d2,(%a0)+
        addq.l  #1,%d6
        and.l   #PLK_MASK,%d6
        subq.l  #1,%d7
        bne.w   9b
        move.l  %d6,(%a6)
        lea     12(%sp),%sp
        moveq   #14,%d1                           | DRV
        bsr.w   dg_drvpass

        move.w  P_LEV(%a3),%d1                    | the level, LEV^2
        ext.l   %d1
        muls.l  %d1,%d1
        moveq   #15,%d2
        asr.l   %d2,%d1
        move.l  %d1,%d4
        lsl.l   %d2,%d4
        moveq   #0,%d5
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
12:     move.l  (%a0),%d0
        bsr.w   dg_out
        subq.l  #1,%d7
        bne.s   12b
        bra.w   dg_exit

        .section .text4,"ax"
        .align  2

        | dg_drvpass(d1 the knob's offset in the params, a3, a4): the block
        | through dg_drive, as DG SINE's DRV; 0 leaves it. Clobbers d0, d1,
        | d2, d7, a0.
dg_drvpass:
        move.w  (%a3,%d1.l),%d0
        ext.l   %d0
        asr.l   #6,%d0
        ble.s   2f
        moveq   #21,%d2
        add.l   %d0,%d2
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
1:      move.l  (%a0),%d0
        bsr.w   dg_drive
        move.l  %d0,(%a0)+
        subq.l  #1,%d7
        bne.s   1b
2:      rts

        .section .text5,"ax"
        .align  2
        | dg_ampdec(d0 envelope, d1.w DEC, 8.8) -> d0: the amplitude
        | envelope's step. DEC 0..100 decay over dg_decay's whole range (its
        | knob = DEC * 1.26); 101..126 loop: dg_decay at knob 10 + 2 (DEC -
        | 101), starting again at full once it is 36 dB down, a pulse every
        | 11 ms (101) to about 1 s (126); 127 holds. Clobbers d1.
dg_ampdec:
        ext.l   %d1
        cmp.l   #0x7eff,%d1
        bgt.w   dg_decay                          | hold
        cmp.l   #0x6500,%d1
        bge.s   1f
        muls.w  #323,%d1                          | * 1.262
        asr.l   #8,%d1
        cmp.l   #0x7e00,%d1
        ble.w   dg_decay
        move.l  #0x7e00,%d1
        bra.w   dg_decay
1:      sub.l   #0x6500,%d1                       | loop: knob 10 + 2 (DEC - 101)
        add.l   %d1,%d1
        add.l   #0x0a00,%d1
        bsr.w   dg_decay
        cmp.l   #0x01000000,%d0
        bcc.s   2f
        move.l  #ENV_FULL,%d0
2:      rts

        .section .text4,"ax"
        .align  2
        | dg_noipass(d1 the knob's offset, a3, a4): adds white noise at the
        | knob's level (127 about full scale), the seed in the voice's SDRAM
        | state at +32. Clobbers d0, d1, d2, d5, d7, a0, a1.
dg_noipass:
        move.w  (%a3,%d1.l),%d2
        ext.l   %d2
        ble.s   2f
        move.l  A_VOICE+4(%sp),%d0
        lsl.l   #8,%d0
        add.l   #EXT_STATE+32,%d0
        movea.l %d0,%a1
        move.l  (%a1),%d0
        move.l  #1664525,%d5
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
1:      mulu.l  %d5,%d0
        add.l   #1013904223,%d0
        move.l  %d0,%d1
        swap    %d1
        ext.l   %d1
        muls.l  %d2,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        add.l   %d1,(%a0)+
        subq.l  #1,%d7
        bne.s   1b
        move.l  %d0,(%a1)
2:      rts

        .section .text6,"ax"
        .align  2
        | the chords, four notes each in semitones: MAJ MIN SUS2 SUS4 MAJ7
        | MIN7 7 M7b5 DIM7 AUG 6 m6 ADD9 m9 5TH OCT
chord_tab:
        .byte   0, 4, 7, 12,   0, 3, 7, 12,   0, 2, 7, 12,   0, 5, 7, 12
        .byte   0, 4, 7, 11,   0, 3, 7, 10,   0, 4, 7, 10,   0, 3, 6, 10
        .byte   0, 3, 6, 9,    0, 4, 8, 12,   0, 4, 7, 9,    0, 3, 7, 9
        .byte   0, 4, 7, 14,   0, 3, 10, 14,  0, 7, 12, 19,  0, 12, 19, 24
chord_det:
        .byte   0, 2, -2, 1
chord_st:
        .byte   ST_PH1, ST_PH2, ST_PH3, ST_PH4
        .align  2
        | the JP-8000's relative spacing at full DET, Q16
super_k:
        .word   -7210, -4121, -1279, 0, 1305, 4074, 7042
        .align  2
super_seed:
        .long   0x00000000, 0x9e3779b9, 0x3c6ef372, 0xdaa66d2b
        .long   0x78dde6e4, 0x1715609d, 0xb54cda56
txt_chord_long: .asciz  "DG CHORD"
txt_chord_short: .asciz "DCHD"
txt_super_long: .asciz  "DG SUPER"
txt_super_short: .asciz "DSUP"
txt_pluck_long: .asciz  "DG PLUCK"
txt_pluck_short: .asciz "DPLK"
txt_chd_l:      .asciz  "Chord"
txt_chd_s:      .asciz  "CHD"
txt_inv_l:      .asciz  "Inversion"
txt_inv_s:      .asciz  "INV"
txt_mix_l:      .asciz  "Mix"
txt_mix_s:      .asciz  "MIX"
txt_brt_l:      .asciz  "Brightness"
txt_brt_s:      .asciz  "BRT"
txt_noi_l:      .asciz  "Noise"
txt_noi_s:      .asciz  "NOI"
txt_pik_l:      .asciz  "Pick Position"
txt_pik_s:      .asciz  "PIK"
txt_len_l:      .asciz  "Pluck Length"
txt_len_s:      .asciz  "LEN"
        .align  2

        | ------------------------------------------------------------ DG CHIP
        | The NES's voices: WAV 0..3 a pulse at 1/8, 1/4, 1/2 and 3/4 (as
        | DG PULSE's, band-limited), 4 the 32-step triangle, 5 and 6 the
        | 15-bit noise in long and short (metallic) mode, clocked at 8 times
        | the note. DEC in the NES's 16 volume steps. ARP 1..16 cycles the
        | four notes of DG CHORD's chord ARP - 1 (0 off), SPD its rate, a step
        | every 100 blocks (67 ms) at 0 to every 6 (4 ms) at 127; SWP slides
        | the pitch down (< 64) or up (> 64) from the trig, up to 5 octaves.
        | State: +8 the phase (or the noise clock), +12 the noise register,
        | +16 the slide (semitones, 16.16), +28 the arp (step << 16 | blocks).
        | In .text6, far from the helpers, so every call is a jsr.
        .equ    P_CWAV,         8                 | 13
        .equ    P_ARP,          10                | 14
        .equ    P_ASPD,         12                | 15
        .equ    P_SWP,          14                | 16
        .equ    SWP_MAX,        60 << 16
dg_chip:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        jsr     dg_enter
        tst.l   %d0
        bne.s   1f
        jmp     dg_exit
1:      tst.l   ST_PH2(%a2)
        bne.s   2f
        moveq   #1,%d0
        move.l  %d0,ST_PH2(%a2)                   | the noise register, never 0
2:      jsr     dg_note                           | d3 the note
        move.w  P_SWP(%a3),%d0                    | the slide
        ext.l   %d0
        sub.l   #0x4000,%d0
        asr.l   #8,%d0
        muls.w  #67,%d0
        add.l   ST_PH3(%a2),%d0
        cmp.l   #SWP_MAX,%d0
        ble.s   21f
        move.l  #SWP_MAX,%d0
21:     cmp.l   #-SWP_MAX,%d0
        bge.s   22f
        move.l  #-SWP_MAX,%d0
22:     move.l  %d0,ST_PH3(%a2)
        add.l   %d0,%d3
        move.w  P_ARP(%a3),%d0                    | the arpeggio
        ext.l   %d0
        asr.l   #8,%d0
        ble.s   4f
        subq.l  #1,%d0
        lsl.l   #2,%d0
        lea     chord_tab,%a0
        adda.l  %d0,%a0
        move.l  ST_PH4(%a2),%d1
        move.l  %d1,%d2
        swap    %d2
        moveq   #3,%d0
        and.l   %d0,%d2
        move.b  (%a0,%d2.l),%d0
        extb.l  %d0
        swap    %d0
        clr.w   %d0
        add.l   %d0,%d3
        addq.l  #1,%d1
        move.w  P_ASPD(%a3),%d0                   | blocks a step: 6 + (127 - SPD)^2 / 170
        ext.l   %d0
        asr.l   #8,%d0
        neg.l   %d0
        add.l   #127,%d0
        muls.l  %d0,%d0
        muls.w  #385,%d0
        clr.w   %d0
        swap    %d0
        addq.l  #6,%d0
        move.l  %d1,%d2
        and.l   #0xffff,%d2
        cmp.l   %d0,%d2
        blt.s   3f
        clr.w   %d1
        add.l   #0x10000,%d1
3:      move.l  %d1,ST_PH4(%a2)
4:      move.l  %d3,%d0
        jsr     dg_inc
        move.l  %d0,%d6                           | the increment

        move.w  P_CWAV(%a3),%d2
        ext.l   %d2
        asr.l   #8,%d2
        bge.s   5f
        moveq   #0,%d2
5:      move.l  ST_PH1(%a2),%d3
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
        moveq   #4,%d0
        cmp.l   %d0,%d2
        beq.s   20f
        bgt.s   30f
        lea     chip_pw,%a1                       | pulse
        move.l  (%a1,%d2.l*4),%d0
        movea.l %d0,%a5
        jsr     dg_kdt
10:     move.l  %d3,%d0
        add.l   %a5,%d0
        jsr     dg_blep
        movea.l %d0,%a6
        move.l  %d3,%d0
        jsr     dg_blep
        move.l  %a6,%d1
        sub.l   %d1,%d0
        asr.l   #1,%d0
        move.l  %d0,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   10b
        bra.s   40f
20:     move.l  %d3,%d0                           | triangle: 15..0..15 in 32 steps
        moveq   #27,%d1
        lsr.l   %d1,%d0
        moveq   #16,%d1
        cmp.l   %d1,%d0
        bge.s   21f
        neg.l   %d0
        add.l   #15,%d0
        bra.s   22f
21:     sub.l   %d1,%d0
22:     add.l   %d0,%d0
        sub.l   #15,%d0
        muls.w  #2184,%d0                         | -15..15 to Q15
        move.l  %d0,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   20b
        bra.s   40f
30:     moveq   #1,%d5                            | noise: the tap, 1 long, 6 short
        moveq   #5,%d0
        cmp.l   %d0,%d2
        beq.s   31f
        moveq   #6,%d5
31:     move.l  %d6,%d4                           | the clock, 8 times the note
        cmp.l   #0x1fffffff,%d4
        bls.s   32f
        move.l  #0x1fffffff,%d4
32:     lsl.l   #3,%d4
        move.l  ST_PH2(%a2),%d2
33:     add.l   %d4,%d3
        bcc.s   34f
        move.l  %d2,%d0
        lsr.l   %d5,%d0
        eor.l   %d2,%d0
        moveq   #1,%d1
        and.l   %d1,%d0
        moveq   #14,%d1
        lsl.l   %d1,%d0
        lsr.l   #1,%d2
        or.l    %d0,%d2
34:     move.l  #24000,%d0
        btst    #0,%d2
        beq.s   35f
        neg.l   %d0
35:     move.l  %d0,(%a0)+
        subq.l  #1,%d7
        bne.s   33b
        move.l  %d2,ST_PH2(%a2)
40:     move.l  %d3,ST_PH1(%a2)

        move.l  ST_ENV(%a2),%d0                   | the level: DEC in 16 steps
        move.w  P_DEC(%a3),%d1
        jsr     dg_ampdec
        move.l  %d0,ST_ENV(%a2)
        and.l   #0x7c000000,%d0
        moveq   #15,%d2
        lsr.l   %d2,%d0
        move.w  P_LEV(%a3),%d1
        ext.l   %d1
        muls.l  %d1,%d1
        asr.l   %d2,%d1
        muls.l  %d1,%d0
        move.l  %d0,%d4
        moveq   #0,%d5
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
41:     move.l  (%a0),%d0
        jsr     dg_out
        subq.l  #1,%d7
        bne.s   41b
        jmp     dg_exit

        .text
        .align  2
chip_pw:
        .long   0x20000000, 0x40000000, 0x80000000, 0xc0000000
txt_chip_long:  .asciz  "DG CHIP"
txt_chip_short: .asciz  "DCHP"
txt_cwav_l:     .asciz  "Waveform"
txt_cwav_s:     .asciz  "WAV"
txt_arp_l:      .asciz  "Arpeggio"
txt_arp_s:      .asciz  "ARP"
txt_aspd_l:     .asciz  "Arp Speed"
txt_aspd_s:     .asciz  "SPD"
txt_swp_l:      .asciz  "Sweep"
txt_swp_s:      .asciz  "SWP"
        .align  2

        .align  2
        .section .text4,"ax"
        .align  2
        | every id 0021 reuses but the template; the sentinel last, then 0
fix_ids:
        .word   408, 409, 411, 412, 413, 414
        .word   416, 417, 418, 419, 421
        .word   422, 423, 424, 425, 426, 427, 428, 429
        .word   430, 431, 432, 433, 434, 443, 444, 445
        .word   435, 436, 437, 438, 439, 440, 441, 442
        .word   449, 450, 451, 452, 453, 454, 455              | batch 3
        .word   415, 398, 399, 400, 401, 402
        .word   403, 404, 405, 406, 407
        .word   447, 448, 390, 391, 392, 393, 394, 395, 396
        .word   382, 383, 384, 385, 386, 387, 388, 389
        .word   ID_SENTINEL, 0
