        | Mod 0028 - the recorder's buffer is a sample slot (LIVE, slot 127).
        |
        | The stock recorder runs every audio interrupt: 0x4013f56c, called
        | through a0 at 0x40121394 from `lea 0x4013f56c,%a0` at 0x40121366. It
        | writes the recording mono, 16-bit, at REC_BUF (the high 16 bits; the
        | low 8 go to a plane of their own), at most REC_MAX samples, and stops
        | at the target RLEN sets. Its state, at REC_STATE: 0 idle, 1 armed,
        | 2 recording, 3 done. SAMPLING + YES drives it from any screen
        | (SamplerLedView, 0x40138142): idle -> arm, armed -> record,
        | recording -> stop; SAMPLING + NO discards.
        |
        | live_rec is a detour on the recorder's single exit, its epilogue at
        | 0x4013f866 (`moveml %sp@,%d2-%d4/%a2; lea %sp@(16),%sp; rts`),
        | re-emitted at the end. (The call site's lea is 0013's.) The block a
        | recording completes leaves by another path (0x4013f856) and is missed;
        | the next block, in state 3, is not. It then points slot LIVE's table
        | entry (0x41329e70 + 16 * slot, as 0x4011bf1e writes it: +0 the data,
        | +4 the rate word, +8 the length in samples, +12 the rate ratio, 1.0 =
        | 0x40000000) at REC_BUF:
        |   - recording: the length is the target, so a trig a few ms after the
        |     recording starts plays it while it is written, and STA/END span
        |     the whole RLEN;
        |   - done: the length is what was recorded.
        | The rate word at +4 is left as it was: the trig copies +0, +8 and +12
        | only, and the ratio at +12 already says 48 kHz.
        | The sample layer copies the entry into the voice at each trig, in the
        | same interrupt, so nothing races. The stock preview (Fn+YES in the
        | trim view) points slot 130 at the same buffer the same way.
        .equ    REC_STATE,      0x419f0330
        .equ    REC_TARGET,     0x419f031c        | samples to record
        .equ    REC_COUNT,      0x419f0320        | samples recorded
        .equ    REC_BUF,        0x42c62190        | 16-bit words
        .equ    REC_MAX,        1584000           | the buffer, 33 s
        .equ    SLOTS,          0x41329e70
        .equ    LIVE,           127
        .equ    RATIO_1,        0x40000000

        .text
        .align  2
live_rec:
        move.l  REC_STATE,%d0                     | d0, d1, a0, a1 are free: the
        subq.l  #2,%d0                            | epilogue restores the rest
        beq.s   1f                                | recording: the target
        subq.l  #1,%d0
        bne.s   9f                                | idle or armed: leave it
        move.l  REC_COUNT,%d1                     | done: what was recorded
        bra.s   2f
1:      move.l  REC_TARGET,%d1
2:      ble.s   9f
        cmp.l   #REC_MAX,%d1
        ble.s   3f
        move.l  #REC_MAX,%d1
3:      lea     SLOTS+16*LIVE,%a0
        move.l  #REC_BUF,%d0
        move.l  %d0,(%a0)
        move.l  %d1,8(%a0)
        move.l  #RATIO_1,%d0
        move.l  %d0,12(%a0)
9:      movem.l (%sp),%d2-%d4/%a2                 | displaced: the epilogue
        lea     16(%sp),%sp
        rts
