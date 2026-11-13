        | Mod 0023 - the audio interrupt's load, over USB.
        |
        | DMA timer 0 is read at the interrupt's entry and exit and around two
        | sections of its control part; the exit packs block k's four words,
        | and the emitter writes them over voice slot 7 of the receive buffer
        | during block k+1, just before stock hands that buffer to USB. See
        | mod.toml for the words; tools/isr_meter.py reads them.
        |
        | Detours (registry/allocations.toml, 0023-isr-meter):
        |   m_in     0x4011fafa  entry: `linkw %fp,#-180; moveml %d0-%a5,%sp@`
        |   m_s1a    0x40120c88  S1 start: `jsr 0x4010e3b4`
        |   m_s1b    0x40120e32  S1 end, S2 start: `tstl 0x8000fce8`
        |   m_s2b    0x40120fa8  S2 end: `movel 0x40287c9c,%sp@-`
        |   m_emit   0x40121434  before USB: `pea 0x80007440`
        |   m_out    0x4012163a  exit: `moveml %fp@(-32),%d0-%d6/%a0`

        .equ    DTCN0,          0xfc07000c        | DMA timer 0, about 130 MHz
        .equ    RXBUF,          0x80007440        | receive buffer, voice slot s at +8 + 4s
        .equ    RXSTRIDE,       48
        .equ    FRAMES,         32
        .equ    T_SLOT,         8 + 4 * 7         | voice slot 7: USB channel 10

        .equ    IN_RESUME,      0x4011fb02
        .equ    S1A_RESUME,     0x40120c8e
        .equ    PRE_S1,         0x4010e3b4
        .equ    S1B_RESUME,     0x40120e38
        .equ    S2B_RESUME,     0x40120fae
        .equ    EMIT_RESUME,    0x4012143a
        .equ    OUT_RESUME,     0x40121640

        .equ    LFO_ARG,        0x40287c9c
        .equ    SCENE_ON,       0x8000fce8

        .text

        | m_in: the prologue, re-emitted; then d0 and d1, which the next stock
        | instructions overwrite, hold the timer.
        .align  2
m_in:
        link    %fp,#-180
        movem.l %d0-%a5,(%sp)
        move.l  DTCN0,%d0
        move.l  %d0,%d1
        sub.l   m_t0,%d1
        move.l  %d1,m_iv
        move.l  %d0,m_t0
        jmp     IN_RESUME

        | m_s1a: the displaced call first, then the mark; d0 is free after
        | the call (the smoothing loop sets it before reading it, and 0024's
        | detour sets it too).
        .align  2
m_s1a:
        jsr     PRE_S1                            | displaced
        move.l  DTCN0,%d0
        move.l  %d0,m_t1
        jmp     S1A_RESUME

        | m_s1b: keeps every register; the displaced tst last, as a beqs
        | follows it.
        .align  2
m_s1b:
        lea     -8(%sp),%sp
        movem.l %d0-%d1,(%sp)
        move.l  DTCN0,%d0
        move.l  %d0,m_t2
        move.l  %d0,%d1
        sub.l   m_t1,%d1
        move.l  %d1,m_s1
        movem.l (%sp),%d0-%d1
        lea     8(%sp),%sp
        tst.l   SCENE_ON                          | displaced
        jmp     S1B_RESUME

        | m_s2b: keeps every register.
        .align  2
m_s2b:
        move.l  %d0,-(%sp)
        move.l  DTCN0,%d0
        sub.l   m_t2,%d0
        move.l  %d0,m_s2
        move.l  (%sp)+,%d0
        move.l  LFO_ARG,-(%sp)                    | displaced
        jmp     S2B_RESUME

        | m_out: every data and address register is about to be reloaded
        | from the frame, so all are free here.
        .align  2
m_out:
        move.l  DTCN0,%d0
        sub.l   m_t0,%d0                          | the whole run
        lsr.l   #2,%d0
        move.l  m_iv,%d1
        lsr.l   #2,%d1
        move.l  m_s1,%d2
        move.l  m_s2,%d3
        .irp    r,%d0,%d1,%d2,%d3
        cmp.l   #0xffff,\r
        bls.s   1f
        move.l  #0xffff,\r
1:      lsl.l   #8,\r
        .endr
        or.l    #0xa5000000,%d0
        or.l    #0x5a000000,%d1
        or.l    #0x3c000000,%d2
        or.l    #0xc3000000,%d3
        move.l  %d0,m_w_run
        move.l  %d1,m_w_iv
        move.l  %d2,m_w_s1
        move.l  %d3,m_w_s2
        movem.l -32(%fp),%d0-%d6/%a0              | displaced
        jmp     OUT_RESUME

        | m_emit: keeps every register; the displaced pea last.
        .align  2
m_emit:
        lea     -12(%sp),%sp
        movem.l %d0-%d1/%a0,(%sp)
        lea     RXBUF+T_SLOT,%a0
        moveq   #FRAMES/4-1,%d1
2:      move.l  m_w_run,%d0
        move.l  %d0,(%a0)
        move.l  m_w_iv,%d0
        move.l  %d0,RXSTRIDE(%a0)
        move.l  m_w_s1,%d0
        move.l  %d0,2*RXSTRIDE(%a0)
        move.l  m_w_s2,%d0
        move.l  %d0,3*RXSTRIDE(%a0)
        lea     4*RXSTRIDE(%a0),%a0
        subq.l  #1,%d1
        bpl.s   2b
        movem.l (%sp),%d0-%d1/%a0
        lea     12(%sp),%sp
        pea     RXBUF                             | displaced
        jmp     EMIT_RESUME

        | State, written at run time.
        .align  2
m_t0:   .long   0
m_iv:   .long   0
m_t1:   .long   0
m_t2:   .long   0
m_s1:   .long   0
m_s2:   .long   0
m_w_run: .long  0
m_w_iv: .long   0
m_w_s1: .long   0
m_w_s2: .long   0
