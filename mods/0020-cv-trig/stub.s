        | Mod 0020 - CTRL IN triggers a track.
        |
        | Fixed, no settings: CTRL IN 1 plays T1 (pad 1, BD), CTRL IN 2 plays T5
        | (pad 5, BT), in any CONTROL INPUT mode. A rising gate plays the
        | track as an Overbridge note does, note 60 (the track's own pitch) at
        | velocity 127, once a gate: the note-off follows len_ms later
        | (mod.toml), whatever the gate's length.
        |
        | Detection, in the audio interrupt just after adc_pedal_update
        | (0x40120e9e, every 32 samples, 0.67 ms): the port's raw converter
        | result (ADRSLT, 0xfc094012 + 2p, the value adc_pedal_update smooths)
        | against ON_MV and OFF_MV turned into the port's raw units by stock's
        | own millivolt conversion (0x4013f3fa, the port's calibration), the
        | way the port's CV levels are. The gate goes on above 1.0 V and off
        | below 0.5 V. Each edge bumps a per-port counter and signals the MIDI
        | task's semaphore (0x418fd874) with the kernel's signal (0x40000d0a),
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

        .include "symbols.inc"

        .equ    ISR_RESUME,     0x40120ea4        | past the displaced lea
        .equ    ADRSLT,         0xfc094012        | ports' raw results, words
        .equ    MV_RAW,         0x4013f3fa        | (port, mV) -> raw, as the CV levels
        .equ    ON_MV,          1000              | the gate: on above 1.0 V
        .equ    OFF_MV,         500               | off below 0.5 V
        .equ    PORTS,          2

        .equ    MIDI_SEM,       0x418fd874        | the MIDI task's semaphore
        .equ    SEM_SIGNAL,     0x40000d0a        | (sem), interrupts masked
        .equ    TASK_RESUME,    0x40082d18        | past the displaced pea
        .equ    NOTE_ON,        0x40083ed4        | (track, note, vel, src, 0, -1, 0)
        .equ    NOTE_OFF,       0x4008419e        | (track, note, src)
        .equ    NOTE,           60                | the track's own pitch
        .equ    VEL,            127
        .equ    SRC,            2                 | as Overbridge

        | One trig a gate (2026-11-13): a rising edge plays the track once;
        | the note-off follows LEN_BLOCKS later whatever the gate does, so a
        | long gate no longer holds the note and the falling edge only re-arms.
        | After a trig the port is not looked at for HOLD_BLOCKS, so a bouncing
        | edge cannot trig twice.
        .equ    LEN_BLOCKS,     (P_LEN_MS * 3) / 2   | 0.667 ms a block
        .equ    HOLD_BLOCKS,    3                 | 2 ms

        | Run-time state, cvt_state + :
        .equ    S_GATE,         0                 | + p: gate on
        .equ    S_ON,           2                 | + p: trigs, counted
        .equ    S_OFF,          4                 | + p: note-offs due, counted
        .equ    S_ON_DONE,      6                 | + p: the task's copies
        .equ    S_OFF_DONE,     8
        .equ    S_PLAYING,      10                | + p: track playing, -1 none
        .equ    S_HOLD,         12                | + p: blocks left not looking
        .equ    S_LEN,          14                | + 2p: blocks to the note-off

        .if     LEN_BLOCKS < 1
        .error  "0020-cv-trig: len_ms must be 1 or more"
        .endif
        .if     LEN_BLOCKS > 65535
        .error  "0020-cv-trig: len_ms too long"
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
        bra.s   8f
3:      pea     ON_MV                             | the thresholds, raw
        move.l  %d2,-(%sp)
        jsr     MV_RAW
        addq.l  #8,%sp
        move.l  %d0,%d3
        asr.l   #3,%d3
        pea     OFF_MV
        move.l  %d2,-(%sp)
        jsr     MV_RAW
        addq.l  #8,%sp
        move.l  %d0,%d4
        asr.l   #3,%d4
        lea     ADRSLT,%a0
        mvs.w   (%a0,%d2.l*2),%d0                 | signed, as adc_pedal_update
        asr.l   #3,%d0                            | reads it, and scaled as it is
        tst.b   S_GATE(%a2,%d2.l)
        bne.s   4f
        cmp.l   %d3,%d0                           | off: on above ON_MV
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
4:      cmp.l   %d4,%d0                           | on: re-armed below OFF_MV
        bge.s   8f
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
        move.l  %d2,%d0
        bsr.w   cvt_dest
        subq.l  #1,%d0                            | the track
        bmi.s   4f
        move.l  %d0,%d3
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

        | cvt_dest(d0 = port) -> d0 = the track, 1-based: 1 (T1) for CTRL IN
        | 1, 5 (T5) for CTRL IN 2.
        .align  2
cvt_dest:
        tst.l   %d0
        bne.s   1f
        moveq   #1,%d0
        rts
1:      moveq   #5,%d0
        rts

        | ------------------------------------------------------------------
        | State, written at run time: gates, edge counters, the task's
        | copies, and the track each port plays (-1 none).
        | ------------------------------------------------------------------
        .align  2
cvt_state:
        .byte   0, 0                              | S_GATE
        .byte   0, 0                              | S_ON
        .byte   0, 0                              | S_OFF
        .byte   0, 0                              | S_ON_DONE
        .byte   0, 0                              | S_OFF_DONE
        .byte   -1, -1                            | S_PLAYING
        .byte   0, 0                              | S_HOLD
        .word   0, 0                              | S_LEN
