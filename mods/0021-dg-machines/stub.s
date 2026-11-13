        | Mod 0021 - new digital machines in the hidden machine slots.
        |
        | LITE: the same nine machines, knobs and records as rytm-mods-src's
        | 0021, with the audio-interrupt work cut down (rytm2_second, branch
        | lite). What changed, and why it is cheaper:
        |
        | - Sines come from a 4096-entry Q15 table in the SDRAM 0022 freed
        |   (SIN_TAB), built from the same refined parabola (dg_sin) the
        |   machines used per sample, 128 of its 1025 quarter-wave points a
        |   call, so no interrupt carries the whole build; the machines are
        |   silent for those few blocks after boot (a trig waits for them).
        |   A lookup is 3 instructions where the polynomial was ~25 and a call.
        | - The polyBLEP saw (dg_sawset / dg_sawadd) keeps its phase biased by
        |   0x80000000 inside the loop, so the naive saw is the phase's top
        |   word and a wrap is the add's overflow: 10 instructions a sample;
        |   the residual (dg_bfix_b, dg_bfix_a, one divide each) runs only on
        |   the two samples at each wrap. Its gain is applied in the pass, so
        |   CHORD and SUPER need no separate clear or scaling.
        | - No subroutine call inside any per-sample loop: the level, drive
        |   and sub passes are inlined loops.
        | - DG PLUCK carries f[k] into the next sample's f[k-1] and the two
        |   string taps it shares, so a sample reads the line once and
        |   multiplies four times where it read four times and multiplied six;
        |   the arithmetic is the same.
        | - A voice whose DG envelope has died (ST_ENV 0, DEC below 101 or
        |   127: neither brings it back; the loop range does, so it runs), or
        |   whose string has rung out (every sample of a block within -1..2,
        |   the pluck spent), only clears its buffer until the next trig.
        |   DEC 127 (hold) leaves the note to the AMP envelope, which runs in
        |   the voice hardware: such a voice keeps computing, as before.
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
        | The machines leave the analog circuit reset, as UT IMPULSE does, and
        | write the voice's digital waveform stream (0x80006bf8 + 128v, 32
        | signed 32-bit frames a block), which voice_output_mix sums into the
        | voice's channel ahead of its analog filter and amp.
        |
        | TUNING. TUN is 0..127 in semitones, 64 the base; FIN -64..+63 cents.
        | The note is pitch + (TUN - 64) + FIN, A4 = note 69 = 440 Hz at 48 kHz.
        | The phase increment comes from a 13-entry table of the top octave,
        | linearly interpolated within the semitone and shifted down by whole
        | octaves. Notes are held to 0..127.
        |
        | DEC. 127 holds; 0..100 an exponential decay from about 1.4 ms to 30 s
        | half-life; 101..126 a looping decay (dg_ampdec).
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

        | RAM parameter records (param_info), built at boot; see dg_fixram.
        .equ    PARAM_INFO,     0x419a4888
        .equ    PI_STRIDE,      0x54
        .equ    PI_COPY,        0x34              | flags, range, two std::functions
        .equ    ROM_REC,        0x401bf918
        .equ    ROM_STRIDE,     0x34
        .equ    ID_TEMPLATE,    410               | a plain 0..127 record, unused by stock
        .equ    ID_SENTINEL,    420               | fixed last; differs from the template until then

        | SDRAM 0022 freed, zeroed by the delay's start-up clear.
        .equ    EXT_STATE,      0x4B600000        | + 256v
        .equ    PLK_BUF,        0x4B610000        | + 16 KB v, 4096 longs
        .equ    PLK_HIST,       0x4B630000        | + 16 KB v: the pluck, for PIK
        .equ    SIN_READY,      0x4B650000        | the build's progress, SIN_MAGIC once done;
                                                  | below the table, so a clear upwards
                                                  | takes the mark before the table
        .equ    SIN_TAB,        0x4B650010        | 4096 words, Q15: sin(2 pi i / 4096)
        .equ    SIN_MAGIC,      0x53494E31
        .equ    SIN_CHUNK,      128               | quarter-wave points built a call
        .equ    ZERO_BLK,       0x4B653000        | 128 bytes nothing writes: a silent pluck
        .equ    PLK_MASK,       0xfff
        .equ    PLK_MAXP,       4000              | longest period, samples (12 Hz)

        | the frame every machine keeps: 11 registers saved
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
        .equ    P_CHD,          8                 | 13 (CHORD)
        .equ    P_INV,          10                | 14
        .equ    P_CDT,          12                | 15
        .equ    P_SDT,          8                 | 13 (SUPER)
        .equ    P_MIX,          10                | 14
        .equ    P_BRT,          8                 | 13 (PLUCK)
        .equ    P_PIK,          10                | 14
        .equ    P_LEN,          12                | 15
        .equ    P_CWAV,         8                 | 13 (CHIP)
        .equ    P_ARP,          10                | 14
        .equ    P_ASPD,         12                | 15
        .equ    P_SWP,          14                | 16
        .equ    SWP_MAX,        60 << 16

        | every machine starts the same way
        .macro  DG_ENTRY
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  A_VOICE(%sp),%d7
        movea.l A_PARAMS(%sp),%a3
        movea.l A_CTRL(%sp),%a5
        .endm

        | ==================================================================
        | cave25: DG SINE, DG SAW, the shared passes and helpers.
        | ==================================================================
        .text
        .align  2

        | ------------------------------------------------------------ DG SINE
        | A sine, phase 0 at the trig, with a pitch sweep (SWD up to +63.5
        | semitones, falling away at SWT) and a soft-clip drive (DRV 0 off).
dg_sine:
        DG_ENTRY
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
        move.l  ST_PH1(%a2),%d3
        bsr.w   dg_sinpass
        move.l  %d3,ST_PH1(%a2)
        moveq   #P_DRV,%d1
        bsr.w   dg_drvpass
        movea.l %d6,%a6                           | SUB (16), then the level
        bsr.w   dg_finish
        bra.w   dg_exit

        | ------------------------------------------------------------- DG SAW
        | A band-limited saw (polyBLEP), a second saw DET up to 50 cents above
        | it (DET 0 leaves one, at full scale; else each at half), and a sine
        | an octave below mixed in by SUB (127 is half and half).
dg_saw:
        DG_ENTRY
        bsr.w   dg_enter
        tst.l   %d0
        beq.w   dg_exit
        bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        movea.l %d0,%a6                           | a6 = increment 1
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
        movea.l %d6,%a5                           | a5 = increment 2
        moveq   #1,%d4                            | each at half
        move.l  %a6,%d6
        move.l  ST_PH1(%a2),%d3
        bsr.w   dg_sawset
        move.l  %d3,ST_PH1(%a2)
        move.l  %a5,%d6
        move.l  ST_PH2(%a2),%d3
        bsr.w   dg_sawadd
        move.l  %d3,ST_PH2(%a2)
        bra.s   6f
5:      moveq   #0,%d4                            | DET 0: one saw; saw 2 follows it
        move.l  %a6,%d6
        move.l  ST_PH1(%a2),%d3
        bsr.w   dg_sawset
        move.l  %d3,ST_PH1(%a2)
        move.l  %d3,ST_PH2(%a2)
6:      moveq   #8,%d1                            | DRV
        bsr.w   dg_drvpass
        moveq   #10,%d1                           | NOI
        bsr.w   dg_noipass
        bsr.w   dg_finish
        bra.w   dg_exit

        | dg_finish(a6 the increment, a4 the buffer of Q15 samples): mixes in
        | the sub (SUB, sound index 16), a sine an octave down, then applies
        | the level. Clobbers d0..d7, a0, a1.
dg_finish:
        move.w  P_SUB(%a3),%d2
        ext.l   %d2
        ble.s   dg_levelpass
        move.l  %a6,%d6
        lsr.l   #1,%d6
        move.l  ST_PH3(%a2),%d3
        lea     SIN_TAB,%a1
        movea.l %a4,%a0
        moveq   #20,%d4
        moveq   #FRAMES,%d7
7:      move.l  %d3,%d0
        lsr.l   %d4,%d0
        mvs.w   (%a1,%d0.l*2),%d0
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
        bne.s   7b
        move.l  %d3,ST_PH3(%a2)
        | the level: dg_levelpass with dg_gain's ramp, dg_levelpass_g with
        | the caller's (d4 the gain Q30, d5 its step a frame). Each sample is
        | held to +-32767, then scaled to the full 32-bit stream.
dg_levelpass:
        bsr.w   dg_gain
dg_levelpass_g:
        movea.l %a4,%a0
        move.l  #32767,%d2
        move.l  #-32767,%d3
        moveq   #15,%d6
        moveq   #FRAMES,%d7
        tst.l   %d5
        bne.s   1f
        asr.l   %d6,%d4                           | no ramp (DEC 127): one gain
4:      move.l  (%a0),%d0
        cmp.l   %d2,%d0
        ble.s   5f
        move.l  %d2,%d0
5:      cmp.l   %d3,%d0
        bge.s   6f
        move.l  %d3,%d0
6:      muls.l  %d4,%d0
        add.l   %d0,%d0
        move.l  %d0,(%a0)+
        subq.l  #1,%d7
        bne.s   4b
        rts
1:      move.l  (%a0),%d0
        cmp.l   %d2,%d0
        ble.s   2f
        move.l  %d2,%d0
2:      cmp.l   %d3,%d0
        bge.s   3f
        move.l  %d3,%d0
3:      move.l  %d4,%d1
        asr.l   %d6,%d1
        muls.l  %d1,%d0
        add.l   %d0,%d0
        move.l  %d0,(%a0)+
        add.l   %d5,%d4
        subq.l  #1,%d7
        bne.s   1b
        rts

dg_exit:
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     44(%sp),%sp
        rts

        | ------------------------------------------------------------ helpers

        | dg_sinpass(d3 phase, d6 increment, a4 buffer): a sine over the
        | block from the table, stored; d3 returns advanced. Clobbers d0, d1,
        | d7, a0, a1.
dg_sinpass:
        lea     SIN_TAB,%a1
        movea.l %a4,%a0
        moveq   #20,%d1
        moveq   #FRAMES,%d7
1:      move.l  %d3,%d0
        lsr.l   %d1,%d0
        mvs.w   (%a1,%d0.l*2),%d0
        move.l  %d0,(%a0)+
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   1b
        rts

        | dg_sawset / dg_sawadd / dg_sawsub(d3 phase, d6 increment, d4 a
        | shift, a4 the block): a polyBLEP saw >> d4, stored, added or
        | subtracted. dg_sawmix(d4 its gain, d5 the block's, Q15): the block
        | becomes (block d5 + saw d4) >> 15. d3 returns advanced. Clobbers
        | d0, d1, d2, d7, a0. Inside, d3 is the phase less 2^31: the naive saw
        | (p >> 16) - 32768 is its top word, and the phase reaching 2^32 is
        | the add's signed overflow, so the residual is taken only at the two
        | samples around each wrap. The increment is under 2^31 (note 127),
        | so no sample is both.
        .macro  SAWOUT mode
        .if     \mode == 3
        muls.l  %d4,%d0
        move.l  (%a0),%d1
        muls.l  %d5,%d1
        add.l   %d1,%d0
        asr.l   #8,%d0
        asr.l   #7,%d0
        move.l  %d0,(%a0)+
        .else
        asr.l   %d4,%d0
        .if     \mode == 0
        move.l  %d0,(%a0)+
        .endif
        .if     \mode == 1
        add.l   %d0,(%a0)+
        .endif
        .if     \mode == 2
        sub.l   %d0,(%a0)+
        .endif
        .endif
        .endm
        .macro  SAWPASS mode
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
        cmp.l   %d6,%d3                           | the block opens just after a wrap
        bcc.s   0f
        eori.l  #0x80000000,%d3
        bra.s   7f
0:      eori.l  #0x80000000,%d3
1:      move.l  %d3,%d0
        swap    %d0
        ext.l   %d0                               | the naive saw
        add.l   %d6,%d3
        bvs.s   8f                                | the phase wraps after this sample
2:      SAWOUT  \mode
        subq.l  #1,%d7
        bne.s   1b
9:      eori.l  #0x80000000,%d3
        rts
8:      bsr.w   dg_bfix_b
        SAWOUT  \mode
        subq.l  #1,%d7
        beq.s   9b
7:      move.l  %d3,%d0                           | the sample just after the wrap
        swap    %d0
        ext.l   %d0
        bsr.w   dg_bfix_a
        add.l   %d6,%d3
        bra.s   2b
        .endm
dg_sawset:
        SAWPASS 0
dg_sawadd:
        SAWPASS 1
dg_sawsub:
        SAWPASS 2
dg_sawmix:
        SAWPASS 3

        | dg_bfix_b(d0 the naive saw, d3 the biased phase already advanced
        | past the wrap, d6 dt) -> d0 less (1 - u)^2 / 2, u = (2^32 - p) / dt
        | of the sample's own phase p. Clobbers d1, d2.
dg_bfix_b:
        move.l  %d3,%d1
        eori.l  #0x80000000,%d1                   | the next phase, past the wrap
        neg.l   %d1
        add.l   %d6,%d1                           | 2^32 - p
        bsr.w   dg_bdiv                           | u, Q16
        move.l  #65536,%d2
        sub.l   %d1,%d2                           | 1 - u
        cmp.l   #65535,%d2
        bls.s   1f
        move.l  #65535,%d2
1:      mulu.l  %d2,%d2
        clr.w   %d2
        swap    %d2                               | (1 - u)^2
        lsr.l   #1,%d2
        sub.l   %d2,%d0
        rts

        | dg_bfix_a(d0 the naive saw, d3 the biased phase, under dt past the
        | wrap) -> d0 less (2t - t^2 - 1) / 2, t = p / dt. Clobbers d1, d2.
dg_bfix_a:
        move.l  %d3,%d1
        eori.l  #0x80000000,%d1                   | p
        bsr.w   dg_bdiv                           | t, Q16
        move.l  %d1,%d2
        mulu.l  %d2,%d2
        clr.w   %d2
        swap    %d2                               | t^2
        add.l   %d1,%d1
        sub.l   %d2,%d1
        sub.l   #65536,%d1                        | 2t - t^2 - 1, -1..0
        asr.l   #1,%d1
        sub.l   %d1,%d0
        rts

        | dg_bdiv(d1 x <= dt, d6 dt) -> d1 = x / dt, Q16: both shifted down
        | until dt fits 16 bits, then one divide.
dg_bdiv:
        move.l  %d2,-(%sp)
        move.l  %d6,%d2
        cmp.l   #0xffffff,%d2
        bls.s   1f
        lsr.l   #8,%d2
        lsr.l   #8,%d1
1:      cmp.l   #0xffff,%d2
        bls.s   2f
        lsr.l   #1,%d2
        lsr.l   #1,%d1
        bra.s   1b
2:      swap    %d1
        clr.w   %d1
        divu.l  %d2,%d1
        move.l  (%sp)+,%d2
        rts

        | dg_enter(d7 voice, a3 params, a5 ctrl) -> a2 state, a4 waveform
        | buffer, d0 = 0 when silent: no trig since the machine was set, its
        | envelope has died for good, or SIN_TAB is still being built; the
        | buffer is then zeroed and the machine returns at once. Clears the
        | voice's noise buffer and gains every block; on a trig resets the
        | circuit and the state. Clobbers d0..d6, a0, a1.
dg_enter:
        jsr     dg_fixram
        move.l  %d7,%d0
        lsl.l   #5,%d0
        add.l   #MSTATE,%d0
        movea.l %d0,%a2
        move.l  %d7,%d0
        lsl.l   #3,%d0
        add.l   #NOISE_GAIN,%d0
        movea.l %d0,%a0
        moveq   #0,%d1
        move.l  %d1,(%a0)+
        move.l  %d1,(%a0)
        move.l  %d7,%d0
        moveq   #7,%d1
        lsl.l   %d1,%d0
        movea.l %d0,%a4
        adda.l  #WAVE_BUF,%a4
        movea.l %d0,%a0
        adda.l  #NOISE_BUF,%a0
        bsr.w   dg_zero8
        movem.l %d0-%d6/%a1,(%a0)
        movem.l %d0-%d6/%a1,32(%a0)
        movem.l %d0-%d6/%a1,64(%a0)
        movem.l %d0-%d6/%a1,96(%a0)

        move.l  SIN_READY,%d0
        cmp.l   #SIN_MAGIC,%d0
        beq.s   1f
        jsr     dg_mksin
        tst.l   %d0
        beq.s   3f                                | still building
1:      move.l  ST_RUN(%a2),%d0
        bmi.s   3f
        bne.s   2f
        move.l  %a5,-(%sp)                        | a trig
        move.l  %d7,-(%sp)
        jsr     VOICE_RESET
        addq.l  #8,%sp
        moveq   #1,%d0
        move.l  %d0,ST_RUN(%a2)
        moveq   #0,%d0
        move.l  %d0,ST_PH1(%a2)
        move.l  %d0,ST_PH2(%a2)
        move.l  %d0,ST_PH3(%a2)
        move.l  %d0,ST_PH4(%a2)
        move.l  #ENV_FULL,%d0
        move.l  %d0,ST_ENV(%a2)
        move.l  %d0,ST_SWE(%a2)
2:      move.l  #ENV_FULL,%d1                     | envelopes held to 0..1, so a
        cmp.l   ST_ENV(%a2),%d1                   | state another path left can
        bcc.s   5f                                | never overflow the gain
        move.l  %d1,ST_ENV(%a2)
5:      cmp.l   ST_SWE(%a2),%d1
        bcc.s   6f
        move.l  %d1,ST_SWE(%a2)
6:      tst.l   ST_ENV(%a2)
        bne.s   7f
        move.w  P_DEC(%a3),%d0                    | died: silent unless DEC is in
        ext.l   %d0                               | the loop range, 101..126,
        cmp.l   #0x6500,%d0                       | which starts it again
        blt.s   3f
        cmp.l   #0x7eff,%d0
        bgt.s   3f
7:      moveq   #1,%d0
        rts
3:      bsr.s   dg_zero8
        movem.l %d0-%d6/%a1,(%a4)
        movem.l %d0-%d6/%a1,32(%a4)
        movem.l %d0-%d6/%a1,64(%a4)
        movem.l %d0-%d6/%a1,96(%a4)
        rts

        | dg_zero8: d0..d6 and a1 zero, for a movem of 32 bytes.
dg_zero8:
        moveq   #0,%d0
        move.l  %d0,%d1
        move.l  %d0,%d2
        move.l  %d0,%d3
        move.l  %d0,%d4
        move.l  %d0,%d5
        move.l  %d0,%d6
        movea.l %d0,%a1
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
        move.l  #131,%d2                          | octaves below the table:
        sub.l   %d1,%d2                           | (131 - n) / 12, as * 683 >> 13
        mulu.w  #683,%d2                          | (exact for n 0..127)
        moveq   #13,%d3
        lsr.l   %d3,%d2
        move.l  %d2,%d3
        mulu.w  #12,%d3
        add.l   %d3,%d1
        sub.l   #120,%d1                          | the note in the table's octave
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

        | dg_sin(d0 x, -32768..32767 for -pi..pi) -> d0 sin, Q15. The
        | parabola 4x(1 - |x|) refined by 0.225 (y|y| - y): within 0.1%.
        | Only dg_mksin calls it now. Clobbers d1.
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

        .align  2
        | phase increments at 48 kHz for notes 120..132 (A4 = 440 Hz)
inc_tab:
        .long   749115498, 793660223, 840853716, 890853480
        .long   943826385, 999949222, 1059409297, 1122405052
        .long   1189146729, 1259857073, 1334772074, 1414141751
        .long   1498230996

        | ==================================================================
        | cave26: DG PULSE and DG FM2.
        | ==================================================================
        .section .text2,"ax"
        .align  2

        | ----------------------------------------------------------- DG PULSE
        | A band-limited pulse, the difference of two polyBLEP saws PW apart
        | (so it has no DC at any width), PW 64 square. PWD sweeps the width
        | with a triangle at PWR; SUB as DG SAW's.
dg_pulse:
        DG_ENTRY
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
1:      add.l   %d0,%d0
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
2:      cmp.l   #0x7e000000,%d0
        ble.s   3f
        move.l  #0x7e000000,%d0
3:      add.l   %d0,%d0
        movea.l %d0,%a5                           | width, Q32
        move.l  %a6,%d6
        move.l  ST_PH1(%a2),%d3
        movea.l %d3,%a1
        moveq   #1,%d4                            | saw(p) / 2 - saw(p + w) / 2
        bsr.w   dg_sawset
        move.l  %d3,ST_PH1(%a2)
        move.l  %a1,%d3
        add.l   %a5,%d3
        bsr.w   dg_sawsub
        bsr.w   dg_finish
        bra.w   dg_exit

        | ------------------------------------------------------------- DG FM2
        | Two-operator FM: a sine carrier at the note, phase-modulated by a sine
        | modulator at RAT's ratio (0..15: 1/2 1 3/2 2 5/2 3 7/2 4 5 6 7 8 9 10
        | 12 16), index FMA up to about 2 pi, falling away at FMD (127 holds);
        | FB the modulator's own feedback.
dg_fm2:
        DG_ENTRY
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
1:      moveq   #15,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      lea     fm_ratio,%a1
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
        move.w  P_FB(%a3),%d1
        ext.l   %d1
        movea.l %d1,%a3                           | FB, the params done with
        move.l  ST_PH1(%a2),%d3                   | carrier phase
        move.l  ST_PH2(%a2),%d2                   | modulator phase
        movea.l ST_PH3(%a2),%a1                   | the modulator's last output
        movea.l %a4,%a0
        lea     SIN_TAB,%a4
        moveq   #FRAMES,%d7
3:      move.l  %a1,%d0
        move.l  %a3,%d1
        muls.l  %d1,%d0
        swap    %d0                               | feedback, up to pi / 2
        move.l  %d2,%d1
        swap    %d1
        add.l   %d1,%d0                           | the low word is the phase
        and.l   #0xfff0,%d0
        lsr.l   #3,%d0
        mvs.w   (%a4,%d0.l),%d0                   | the modulator
        movea.l %d0,%a1
        move.l  %a5,%d1
        muls.l  %d1,%d0
        asr.l   #8,%d0
        asr.l   #6,%d0                            | phase offset, up to 2 pi
        move.l  %d3,%d1
        swap    %d1
        add.l   %d1,%d0
        and.l   #0xfff0,%d0
        lsr.l   #3,%d0
        mvs.w   (%a4,%d0.l),%d0                   | the carrier, never past 32767
        move.l  %d4,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        muls.l  %d1,%d0
        add.l   %d0,%d0
        move.l  %d0,(%a0)+
        add.l   %d5,%d4
        add.l   %a6,%d2
        add.l   %d6,%d3
        subq.l  #1,%d7
        bne.s   3b
        move.l  %d3,ST_PH1(%a2)
        move.l  %d2,ST_PH2(%a2)
        move.l  %a1,ST_PH3(%a2)
        bra.w   dg_exit

        | ==================================================================
        | cave27: DG CHORD, the pluck's excitation, DG SUPER.
        | ==================================================================
        .section .text3,"ax"
        .align  2

        | ----------------------------------------------------------- DG CHORD
        | Four polyBLEP saws on a chord from CHD's table (16 chords), the
        | lowest INV notes raised an octave, DET spreading them up to about
        | 12 cents. Each saw at a quarter, so the four never clip.
dg_chord:
        DG_ENTRY
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
1:      bsr.w   dg_note                           | d3 the root
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
        moveq   #2,%d4                            | each at a quarter
        suba.l  %a5,%a5
6:      move.l  %a5,%d0
        move.l  (%sp,%d0.l*4),%d6
        lea     chord_st,%a1
        mvz.b   (%a1,%d0.l),%d1
        move.l  (%a2,%d1.l),%d3
        tst.l   %d0
        bne.s   61f
        bsr.w   dg_sawset
        bra.s   62f
61:     bsr.w   dg_sawadd
62:     move.l  %a5,%d0
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
        | state) -> d0 = 0 when the pluck is spent (the block left as it is),
        | else 1 and the block holds this block's share of the pluck:
        | BRT-low-passed differenced noise less its PIK comb, then zeros.
        | Clobbers d0..d3, d6, d7, a0, a1.
plk_excite:
        move.l  4(%a6),%d7
        bne.s   0f
        moveq   #0,%d0
        rts
0:      bsr.w   dg_clrbuf
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
        moveq   #1,%d0
        rts

        | dg_clrbuf(a4): zeroes the block. Clobbers d0, d1, a0.
dg_clrbuf:
        movea.l %a4,%a0
        moveq   #0,%d0
        moveq   #8,%d1
1:      move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bne.s   1b
        rts

        | ----------------------------------------------------------- DG SUPER
        | Seven polyBLEP saws, the outer six detuned by DET (squared, up to
        | about +-1.9 semitones at the edges, the JP-8000's spacing), MIX
        | raising the six and lowering the centre. Phases free-run from a
        | spread seed at the trig, in the voice's SDRAM state.
dg_super:
        DG_ENTRY
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
2:      bsr.w   dg_note
        move.l  %d3,%d0
        bsr.w   dg_inc
        move.l  %d0,ST_PH2(%a2)                   | the centre's increment
        suba.l  %a5,%a5                           | k: the sides first, raw,
        tst.w   P_MIX(%a3)                        | then the centre (3) mixing
        bne.s   3f                                | them in at MIX's gain;
        moveq   #6,%d0                            | MIX 0 leaves the centre
        movea.l %d0,%a5
3:      lea     super_ord,%a0
        move.l  %a5,%d0
        mvz.b   (%a0,%d0.l),%d0
        movea.l %d0,%a1                           | i, the saw
        move.w  P_SDT(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        muls.l  %d0,%d0
        add.l   %d0,%d0                           | DET^2, Q15
        move.l  %a1,%d1
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
        move.l  %a1,%d0
        move.l  (%a6,%d0.l*4),%d3
        moveq   #6,%d0
        cmpa.l  %d0,%a5
        beq.s   5f
        moveq   #0,%d4
        move.l  %a5,%d0
        bne.s   4f
        bsr.w   dg_sawset
        bra.s   6f
4:      bsr.w   dg_sawadd
        bra.s   6f
5:      move.w  P_MIX(%a3),%d0
        ext.l   %d0
        asr.l   #8,%d0
        move.l  %d0,%d5                           | sides: MIX * 32
        lsl.l   #5,%d5
        moveq   #48,%d4                           | centre: 0.5 less MIX * 48
        muls.l  %d0,%d4
        neg.l   %d4
        add.l   #16384,%d4
        bsr.w   dg_sawmix
6:      move.l  %a1,%d0
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

        | ==================================================================
        | cave28: the DRV and NOI passes, and the DEC curve.
        | ==================================================================
        .section .text4,"ax"
        .align  2

        | dg_drvpass(d1 the knob's offset in the params, a3, a4): the block
        | through the soft clip u = clamp(y g), u (1.5 - 0.5u^2), g = 21/32 +
        | DRV / 8 (about unity for small signals at the knob's first step);
        | 0 leaves it. Clobbers d0..d3, d7, a0.
dg_drvpass:
        move.w  (%a3,%d1.l),%d0
        ext.l   %d0
        asr.l   #6,%d0
        ble.s   9f
        moveq   #21,%d2
        add.l   %d0,%d2
        moveq   #15,%d3
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
1:      move.l  (%a0),%d0
        muls.l  %d2,%d0
        asr.l   #5,%d0
        cmp.l   #32767,%d0
        ble.s   2f
        move.l  #32767,%d0
2:      cmp.l   #-32767,%d0
        bge.s   3f
        move.l  #-32767,%d0
3:      move.l  %d0,%d1
        muls.l  %d1,%d1
        clr.w   %d1
        swap    %d1                               | u^2 / 2, Q15
        neg.l   %d1
        add.l   #49152,%d1                        | 1.5 - u^2 / 2
        muls.l  %d0,%d1
        asr.l   %d3,%d1
        move.l  %d1,(%a0)+
        subq.l  #1,%d7
        bne.s   1b
9:      rts

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

        | ==================================================================
        | cave29: DG PLUCK.
        | ==================================================================
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
        DG_ENTRY
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
        move.l  %a2,-(%sp)                        | 16(sp): the state
        clr.l   -(%sp)                            | 12(sp): the block's samples, or-ed
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
5:      move.w  P_PIK(%a3),%d0                    | the pick comb's delay, up to
        ext.l   %d0                               | half a period
        mulu.l  %d5,%d0
        clr.w   %d0
        swap    %d0
        move.l  %d0,24(%a6)
        bsr.w   plk_excite
        movea.l %a4,%a2                           | a2: the excitation, read
        tst.l   %d0                               | alongside the output
        bne.s   6f
        lea     ZERO_BLK,%a2
6:      move.l  (%a6),%d6                         | w
        move.l  %d5,%d0
        subq.l  #1,%d0
        movea.l %d0,%a3                           | n - 1, the params done with
        | the window at the block's first k = w - n: x[k], x[k-1], and
        | f[k-1] >> 15; after that each sample reads only x[k+1].
        move.l  %d6,%d0
        sub.l   %d5,%d0
        and.l   #PLK_MASK,%d0
        move.l  (%a5,%d0.l*4),%d2                 | x[k]
        subq.l  #1,%d0
        and.l   #PLK_MASK,%d0
        move.l  (%a5,%d0.l*4),%d3                 | x[k-1]
        subq.l  #1,%d0
        and.l   #PLK_MASK,%d0
        move.l  (%a5,%d0.l*4),%d0                 | x[k-2]
        add.l   %d2,%d0
        muls.l  (%sp),%d0
        move.l  %d3,%d1
        muls.l  4(%sp),%d1
        add.l   %d1,%d0
        asr.l   #8,%d0
        asr.l   #7,%d0
        move.l  %d0,%d5                           | f[k-1] >> 15
        movea.l %a4,%a0
        moveq   #FRAMES,%d7
7:      move.l  %d6,%d0
        sub.l   %a3,%d0
        and.l   #PLK_MASK,%d0
        move.l  (%a5,%d0.l*4),%d1                 | x[k+1]
        move.l  %d1,%d0
        add.l   %d3,%d0
        muls.l  (%sp),%d0                         | cs (x[k+1] + x[k-1])
        move.l  %d2,%d3                           | the window moves on
        move.l  %d1,%d2
        move.l  %d3,%d1
        muls.l  4(%sp),%d1                        | cm x[k]
        add.l   %d1,%d0
        asr.l   #8,%d0
        asr.l   #7,%d0                            | f[k] >> 15
        move.l  %d5,%d1
        move.l  %d0,%d5
        sub.l   %d0,%d1
        muls.l  %d4,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        add.l   %d1,%d0                           | y, between f[k] and f[k-1]
        move.l  %d0,%d1
        muls.l  8(%sp),%d1
        asr.l   #8,%d1
        asr.l   #8,%d1
        sub.l   %d1,%d0                           | less the loss
        add.l   (%a2)+,%d0                        | plus the excitation
        cmp.l   #32767,%d0
        ble.s   71f
        move.l  #32767,%d0
71:     cmp.l   #-32767,%d0
        bge.s   72f
        move.l  #-32767,%d0
72:     move.l  %d0,(%a5,%d6.l*4)
        move.l  %d0,(%a0)+
        addq.l  #1,%d0
        or.l    %d0,12(%sp)                       | y + 1 or-ed: 0..3 while quiet
        addq.l  #1,%d6
        and.l   #PLK_MASK,%d6
        subq.l  #1,%d7
        bne.w   7b
        move.l  %d6,(%a6)
        move.l  12(%sp),%d0
        movea.l 16(%sp),%a2
        lea     20(%sp),%sp
        movea.l A_PARAMS(%sp),%a3
        and.l   #0xfffffffc,%d0                   | the string has rung out and
        bne.s   8f                                | the pluck is spent: silent
        tst.l   4(%a6)                            | until the next trig
        bne.s   8f
        clr.l   ST_ENV(%a2)
8:      moveq   #14,%d1                           | DRV
        bsr.w   dg_drvpass
        move.w  P_LEV(%a3),%d1                    | the level, LEV^2
        ext.l   %d1
        muls.l  %d1,%d1
        moveq   #15,%d2
        asr.l   %d2,%d1
        move.l  %d1,%d4
        lsl.l   %d2,%d4
        moveq   #0,%d5
        bsr.w   dg_levelpass_g
        bra.w   dg_exit

        .section .text4,"ax"
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

        | ==================================================================
        | cave30 (far from the helpers, so every call is a jsr): DG CHIP and
        | the chord tables.
        | ==================================================================
        .section .text6,"ax"
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
dg_chip:
        DG_ENTRY
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
        lea     chip_pw,%a1                       | pulse: (saw(p) - saw(p + w)) / 2
        movea.l (%a1,%d2.l*4),%a5
        movea.l %d3,%a1
        moveq   #1,%d4
        jsr     dg_sawset
        move.l  %d3,ST_PH1(%a2)
        move.l  %a1,%d3
        add.l   %a5,%d3
        jsr     dg_sawsub
        bra.w   41f
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
41:     move.l  ST_ENV(%a2),%d0                   | the level: DEC in 16 steps
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
        jsr     dg_levelpass_g
        jmp     dg_exit

        .align  2
chip_pw:
        .long   0x20000000, 0x40000000, 0x80000000, 0xc0000000
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
super_ord:
        .byte   0, 1, 2, 4, 5, 6, 3
        .align  2
super_seed:
        .long   0x00000000, 0x9e3779b9, 0x3c6ef372, 0xdaa66d2b
        .long   0x78dde6e4, 0x1715609d, 0xb54cda56
fm_ratio:
        .word   128, 256, 384, 512, 640, 768, 896, 1024
        .word   1280, 1536, 1792, 2048, 2304, 2560, 3072, 4096

        | ==================================================================
        | cave25 again: DG ORGAN.
        | ==================================================================
        .text
        .align  2

        | ----------------------------------------------------------- DG ORGAN
        | Four drawbars, sines at 16 ft (an octave down), 8 ft (the note),
        | 5 1/3 ft (a fifth above) and 4 ft (an octave up), D16 D8 D5 D4 their
        | levels; the sum is halved, so two full drawbars reach full scale.
dg_organ:
        DG_ENTRY
        jsr     dg_enter
        tst.l   %d0
        bne.s   0f
        jmp     dg_exit
0:      jsr     dg_note
        move.l  %d3,%d0
        jsr     dg_inc
        move.l  %d0,%d6                           | 8 ft
        jsr     dg_gain
        move.l  %a2,-(%sp)                        | 12(sp): the state
        move.l  %d6,%d0
        add.l   %d0,%d0
        move.l  %d0,-(%sp)                        | 8(sp): 4 ft's increment
        move.l  %d6,%d0
        lsr.l   #1,%d0
        move.l  %d0,%d1
        add.l   %d6,%d1
        move.l  %d1,-(%sp)                        | 4(sp): 5 1/3 ft's
        move.l  %d0,-(%sp)                        | (sp): 16 ft's
        move.l  ST_PH1(%a2),%d3                   | 8 ft
        movea.l ST_PH3(%a2),%a1                   | 5 1/3 ft
        movea.l ST_PH4(%a2),%a5                   | 4 ft
        movea.l ST_PH2(%a2),%a2                   | 16 ft
        movea.l %a4,%a0
        lea     SIN_TAB,%a4
        moveq   #20,%d2
        moveq   #FRAMES,%d7
1:      move.l  %a2,%d0
        lsr.l   %d2,%d0
        mvs.w   (%a4,%d0.l*2),%d0
        muls.w  P_D16(%a3),%d0
        asr.l   #2,%d0
        movea.l %d0,%a6
        move.l  %d3,%d0
        lsr.l   %d2,%d0
        mvs.w   (%a4,%d0.l*2),%d0
        muls.w  P_D8(%a3),%d0
        asr.l   #2,%d0
        adda.l  %d0,%a6
        move.l  %a1,%d0
        lsr.l   %d2,%d0
        mvs.w   (%a4,%d0.l*2),%d0
        muls.w  P_D5(%a3),%d0
        asr.l   #2,%d0
        adda.l  %d0,%a6
        move.l  %a5,%d0
        lsr.l   %d2,%d0
        mvs.w   (%a4,%d0.l*2),%d0
        muls.w  P_D4(%a3),%d0
        asr.l   #2,%d0
        adda.l  %d0,%a6
        move.l  %a6,%d0
        asr.l   #7,%d0
        asr.l   #7,%d0                            | half the sum, Q15
        cmp.l   #32767,%d0
        ble.s   2f
        move.l  #32767,%d0
2:      cmp.l   #-32767,%d0
        bge.s   3f
        move.l  #-32767,%d0
3:      move.l  %d4,%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        muls.l  %d1,%d0
        add.l   %d0,%d0
        move.l  %d0,(%a0)+
        add.l   %d5,%d4
        adda.l  (%sp),%a2
        add.l   %d6,%d3
        adda.l  4(%sp),%a1
        adda.l  8(%sp),%a5
        subq.l  #1,%d7
        bne.w   1b
        move.l  %a2,%d0
        movea.l 12(%sp),%a2
        lea     16(%sp),%sp
        move.l  %d3,ST_PH1(%a2)
        move.l  %d0,ST_PH2(%a2)
        move.l  %a1,ST_PH3(%a2)
        move.l  %a5,ST_PH4(%a2)
        jmp     dg_exit

        | ==================================================================
        | cave10: once after boot, the RAM records and the sine table; and
        | batch 3's names.
        | ==================================================================
        .section .text7,"ax"
        .align  2

        | ------------------------------------------------------------ dg_fixram
        | The RAM parameter records (param_info, built at boot) are not the
        | ROM ones: stock gives some of the reused test-machine ids list flags
        | and label formatters there. Once after boot, the records of every
        | id these machines use take the template's flags, range and
        | formatters, and their top from the ROM record's max. Done when the
        | sentinel matches the template. Clobbers d0, d1, a0, a1.
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

        | ------------------------------------------------------------ dg_mksin
        | SIN_TAB[i] = dg_sin of phase i / 4096, from the quarter wave: point
        | j (0..1024) is written to its four mirror places. SIN_CHUNK points
        | a call, from the progress at SIN_READY (anything past 1025 starts
        | over); -> d0 = 1 and SIN_MAGIC once all are done, else 0.
        | Clobbers d0..d3, a0.
dg_mksin:
        lea     SIN_TAB,%a0
        move.l  SIN_READY,%d2
        cmp.l   #1025,%d2
        bls.s   0f
        moveq   #0,%d2
0:      move.l  %d2,%d0
        add.l   #SIN_CHUNK,%d0
        move.l  %d0,-(%sp)                        | this call's last point + 1
1:      cmp.l   #1024,%d2
        bgt.s   5f
        cmp.l   (%sp),%d2
        bge.s   4f
        move.l  %d2,%d0
        lsl.l   #4,%d0                            | x = 16 j, 0..pi/2
        jsr     dg_sin
        move.w  %d0,(%a0,%d2.l*2)                 | j
        move.l  #2048,%d3
        sub.l   %d2,%d3
        move.w  %d0,(%a0,%d3.l*2)                 | 2048 - j
        neg.l   %d0
        move.l  #2048,%d3
        add.l   %d2,%d3
        move.w  %d0,(%a0,%d3.l*2)                 | 2048 + j
        move.l  #4096,%d3
        sub.l   %d2,%d3
        and.l   #4095,%d3
        move.w  %d0,(%a0,%d3.l*2)                 | 4096 - j
        addq.l  #1,%d2
        bra.s   1b
4:      addq.l  #4,%sp
        move.l  %d2,SIN_READY
        moveq   #0,%d0
        rts
5:      addq.l  #4,%sp
        move.l  #SIN_MAGIC,%d0
        move.l  %d0,SIN_READY
        moveq   #1,%d0
        rts

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

        | ==================================================================
        | cave15: the names of batches 1 and 2.
        | ==================================================================
        .section .text8,"ax"
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
        .section .text7,"ax"
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
        .section .text8,"ax"                      | cave15: DG CHIP's names
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
