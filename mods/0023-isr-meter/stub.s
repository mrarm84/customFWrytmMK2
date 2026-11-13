        | Mod 0023 - the audio interrupt's load, over USB, in twenty sections.
        |
        | DMA timer 0 (DTCN0, about 130 MHz) is read at the interrupt's entry
        | (mark 0), at nineteen points along its main path (marks 1..19), and at
        | its exit (mark 20). The exit packs block k's words; the emitter writes
        | them over voice slot 7 of the receive buffer during block k+1, just
        | before stock hands that buffer to USB (USB channel 10), one word a
        | frame, (tag << 24) | (value << 8):
        |   0x50  the whole run / 4           0x51  the interval / 4
        |   0x52..0x65  section 1..20 in ticks (mark k - mark k-1)
        |   0x66  a block counter             0x67..0x6f  0
        | each held at 0xffff. Marks the alternate path never reaches keep the
        | entry's time, so its sections read 0. tools/isr_meter.py names them.
        |
        | Marks (registry/allocations.toml, 0023-isr-meter):
        |   0  m_in    0x4011fafa  entry
        |   1  m_k1    0x40120c88  before the smoothing
        |   2  m_k2    0x40120e32  after the smoothing and interpolation
        |   3  m_k3    0x40120fa8  before the LFOs
        |   4  m_k4    0x40120fb8  after the LFOs
        |   5  m_k5    0x40121218  after the machine calls, before 0x4011c64c
        |   6  m_k6    0x4012121e  after 0x4011c64c
        |   7  m_k7    0x40121234  after 0x4010ea2c
        |   8  m_k8    0x40121240  after the filter envelopes (0x4010d090)
        |   9  m_k9    0x40121250  after the amp envelopes (0x401098d4)
        |  10  m_k10   0x401212ae  after the mute/solo loop
        |  11  m_k11   0x40121306  after 0013's route_all and the master volume
        |  12  m_k12   0x4012132c  before 0x4010e1a0
        |  13  m_k13   0x40121338  after it, before the return mixers
        |  14  m_k14   0x40121358  before the receive fill
        |  15,16 m_k1516 0x40121396 around the stock FX (0x4010e650)
        |  17  m_k17   0x401213aa  after 0019's fx_post
        |  18  m_emit  0x40121434  before USB, and emits
        |  19  m_k19   0x4012145e  after USB, before the voice DMA copy
        |  20  m_out   0x4012163a  exit
        | Code in cave2 and (the section-6 marks, .mk2) cave7; state (.mdata) in
        | cave6. cave6 and cave7 are 0024's when its half is on: not both.

        .equ    DTCN0,          0xfc07000c        | DMA timer 0, about 130 MHz
        .equ    RXBUF,          0x80007440        | receive buffer, voice slot s at +8 + 4s
        .equ    RXSTRIDE,       48
        .equ    FRAMES,         32
        .equ    T_SLOT,         8 + 4 * 7         | voice slot 7: USB channel 10
        .equ    MARKS,          21
        .equ    WORDS,          32
        .equ    SECTIONS,       MARKS - 1

        .text

        | mark k: keeps every register; the condition codes are not kept.
        .macro  mark k
        move.l  %d0,-(%sp)
        move.l  DTCN0,%d0
        move.l  %d0,m_mk+4*\k
        move.l  (%sp)+,%d0
        .endm

        | m_in: the prologue, re-emitted; then every mark starts at the
        | entry's time. d0, d1 and a0 are written by the next stock code.
        .align  2
m_in:
        link    %fp,#-180
        movem.l %d0-%a5,(%sp)
        move.l  DTCN0,%d0
        move.l  %d0,%d1
        sub.l   m_mk,%d1
        move.l  %d1,m_iv
        lea     m_mk,%a0
        moveq   #MARKS-1,%d1
1:      move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bpl.s   1b
        jmp     0x4011fb02

        .align  2
m_k1:
        jsr     0x4010e3b4                        | displaced
        mark    1
        jmp     0x40120c8e

        .align  2
m_k2:
        mark    2
        tst.l   0x8000fce8                        | displaced, last: a beqs follows
        jmp     0x40120e38

        .align  2
m_k3:
        mark    3
        move.l  0x40287c9c,-(%sp)                 | displaced
        jmp     0x40120fae

        .align  2
m_k4:
        mark    4
        lea     0x80005eac,%a0                    | displaced
        jmp     0x40120fbe

        .align  2
m_k5:
        mark    5
        jsr     0x4011c64c                        | displaced
        jmp     0x4012121e

        .align  2
m_k14:
        mark    14
        jsr     0x4010e944                        | displaced
        jmp     0x4012135e

        | m_k78: over `addql #4,%sp; movel %d2,%sp@` and the first half of
        | `jsr 0x4010e650`, all re-emitted, as 0013's timing build does.
        .align  2
m_k1516:
        mark    15
        addq.l  #4,%sp                            | displaced
        move.l  %d2,(%sp)                         | displaced
        jsr     0x4010e650                        | displaced
        mark    16
        jmp     0x401213a0

        .align  2
m_k17:
        mark    17
        lea     0x8000e4d4,%a0                    | displaced
        jmp     0x401213b0

        .align  2
m_k19:
        mark    19
        pea     0x800063c0                        | displaced
        jmp     0x40121464

        | The section-6 marks, in cave7.
        .section .mk2,"ax"
        .align  2
m_k6:
        mark    6
        move.l  0x42f92124,%d0                    | displaced
        jmp     0x40121224
        .align  2
m_k7:
        mark    7
        pea     0x800063c0                        | displaced
        jmp     0x4012123a
        .align  2
m_k8:
        mark    8
        pea     0x800063c0                        | displaced
        jmp     0x40121246
        .align  2
m_k9:
        mark    9
        move.l  0x8000ed6c,%d2                    | displaced, last: a bges follows
        jmp     0x40121256
        .align  2
m_k10:
        mark    10
        move.l  0x42f92124,%d3                    | displaced
        jmp     0x401212b4
        .align  2
m_k11:
        mark    11
        move.w  0x8000fbce,%d0                    | displaced
        jmp     0x4012130c
        .align  2
m_k12:
        mark    12
        jsr     0x4010e1a0                        | displaced
        jmp     0x40121332
        .align  2
m_k13:
        mark    13
        jsr     0x4010ede2                        | displaced
        jmp     0x4012133e
        .text

        | m_out: every data and address register is about to be reloaded
        | from the frame, so all are free here.
        .align  2
m_out:
        move.l  DTCN0,%d0
        move.l  %d0,m_mk+4*SECTIONS
        lea     m_mk,%a0
        lea     m_w,%a1
        sub.l   (%a0),%d0                         | the whole run
        lsr.l   #2,%d0
        move.l  #0x50,%d2
        bsr.s   m_pack
        move.l  m_iv,%d0
        lsr.l   #2,%d0
        moveq   #0x51,%d2
        bsr.s   m_pack
        moveq   #SECTIONS-1,%d3                   | sections 1..20
1:      move.l  4(%a0),%d0
        sub.l   (%a0)+,%d0
        bpl.s   2f
        moveq   #0,%d0
2:      addq.l  #1,%d2
        bsr.s   m_pack
        subq.l  #1,%d3
        bpl.s   1b
        move.l  m_cnt,%d0
        addq.l  #1,%d0
        move.l  %d0,m_cnt
        and.l   #0xffff,%d0
        moveq   #0x66,%d2
        bsr.s   m_pack
        moveq   #0x6f-0x66-1,%d3                  | the rest 0
3:      moveq   #0,%d0
        addq.l  #1,%d2
        bsr.s   m_pack
        subq.l  #1,%d3
        bpl.s   3b
        movem.l -32(%fp),%d0-%d6/%a0              | displaced
        jmp     0x40121640

        | m_pack(d0 value, d2 tag, a1 the word): held at 0xffff, stored as
        | (tag << 24) | (value << 8), a1 advanced. Uses d0, d1.
m_pack:
        cmp.l   #0xffff,%d0
        bls.s   1f
        move.l  #0xffff,%d0
1:      lsl.l   #8,%d0
        move.l  %d2,%d1
        swap    %d1
        lsl.l   #8,%d1
        or.l    %d1,%d0
        move.l  %d0,(%a1)+
        rts

        | m_emit: mark 10, then the words over slot 7, frame f word f mod 16;
        | keeps every register; the displaced pea last.
        .align  2
m_emit:
        mark    18
        lea     -16(%sp),%sp
        movem.l %d0-%d1/%a0-%a1,(%sp)
        lea     RXBUF+T_SLOT,%a0
        moveq   #FRAMES-1,%d1
        lea     m_w,%a1
1:      move.l  (%a1,%d1.l*4),(%a0)               | frame 31 - d1 gets word d1
        lea     RXSTRIDE(%a0),%a0
        subq.l  #1,%d1
        bpl.s   1b
        movem.l (%sp),%d0-%d1/%a0-%a1
        lea     16(%sp),%sp
        pea     RXBUF                             | displaced
        jmp     0x4012143a

        | State, written at run time, in .mdata (cave22).
        .section .mdata,"aw"
        .align  2
m_iv:   .long   0
m_cnt:  .long   0
m_mk:   .space  4 * MARKS
m_w:    .space  4 * WORDS
