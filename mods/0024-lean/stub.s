        | Mod 0024 - a leaner audio interrupt. See mod.toml.
        |
        | half (detours, registry/allocations.toml):
        |   lean_smooth  0x40120c8e  over `lea 0x8000f774,%a4`: flips the block
        |                parity; on a computing block runs the smoothing, else
        |                jumps past it with a0 as the loop leaves it
        |   lean_interp  0x40120dea  over `lea 0x8000f7a8,%a0`: on a computing
        |                block runs the interpolation, else restores the working
        |                array from the copy and goes on at 0x40120e32
        |   lean_snap    0x40120e6e  over `movel #0x8000f7f6,%d7`: on a computing
        |                block copies the working array, before anything adds
        |                to it in place
        | and two patches squaring the glide's coefficients.
        | cut: two patches only (registry).

        .equ    WORK,           0x8000f774        | the working array, 572 words
        .equ    WORK_LEN,       1144
        .equ    TARGETS,        0x8000e57c        | what the smoothing leaves in a0
        .equ    INTERP_ARR,     0x8000f7a8        | the interpolation's displaced lea
        | The copy is in four code caves, the only memory both free and in the
        | data cache's window (ACR0: 0x40000000..0x47ffffff copyback; the
        | rest, SDRAM at 0x4b... included, is uncached, where the first version
        | kept it: its copies cost about 3.7% of a block). snap0..snap3 below,
        | 512 + 264 + 248 + 120 = 1144 bytes.

        .equ    SMOOTH_RESUME,  0x40120c94
        .equ    SMOOTH_SKIP,    0x40120ce4        | past the loop and its last store
        .equ    INTERP_RESUME,  0x40120df0
        .equ    INTERP_SKIP,    0x40120e32
        .equ    SNAP_RESUME,    0x40120e74
        .equ    SNAP_D7,        0x8000f7f6        | the displaced immediate

        .text

        .if     P_HALF
        | lean_smooth: d0 is set before it is read on both ways on.
        .align  2
lean_smooth:
        move.l  lean_par,%d0
        eori.l  #1,%d0
        move.l  %d0,lean_par
        beq.s   1f
        lea     WORK,%a4                          | displaced
        jmp     SMOOTH_RESUME
1:      lea     TARGETS,%a0                       | read by the loop at 0x40120ce8
        jmp     SMOOTH_SKIP

        | lean_interp: on a skipped block nothing the interpolation leaves in
        | registers is read after 0x40120e32; a3 and fp are live, and kept.
        .align  2
lean_interp:
        tst.l   lean_par
        beq.s   1f
        lea     INTERP_ARR,%a0                    | displaced
        jmp     INTERP_RESUME
1:      lea     -56(%sp),%sp
        movem.l %d0-%d7/%a0-%a5,(%sp)
        moveq   #0,%d0                            | caves -> WORK
        bsr.s   lean_copy
        movem.l (%sp),%d0-%d7/%a0-%a5
        lea     56(%sp),%sp
        jmp     INTERP_SKIP

        | lean_snap: keeps every register; d0 holds 0x4011faea's result,
        | pushed at 0x40120e86.
        .align  2
lean_snap:
        tst.l   lean_par
        beq.s   9f
        lea     -56(%sp),%sp
        movem.l %d0-%d7/%a0-%a5,(%sp)
        moveq   #1,%d0                            | WORK -> caves
        bsr.s   lean_copy
        movem.l (%sp),%d0-%d7/%a0-%a5
        lea     56(%sp),%sp
9:      move.l  #SNAP_D7,%d7                      | displaced
        jmp     SNAP_RESUME

        | lean_copy(d0 = 0 restore, 1 take): WORK against the four caves in
        | turn, 32 bytes a movem, then longs. Uses d0-d7, a0-a5.
        .align  2
lean_copy:
        move.l  %d0,%a5                           | the direction
        lea     WORK,%a4                          | the WORK side, running
        lea     lean_chunks,%a3
1:      move.l  (%a3)+,%a2                        | the cave
        move.l  (%a3)+,%d1                        | its length
        beq.s   9f
        move.l  %a2,%a0                           | from the cave ...
        move.l  %a4,%a1                           | ... to WORK
        move.l  %a5,%d0                           | d0 is set again below
        tst.l   %d0
        beq.s   3f
        move.l  %a4,%a0                           | or from WORK to the cave
        move.l  %a2,%a1
3:      adda.l  %d1,%a4
2:      moveq   #32,%d0
        cmp.l   %d0,%d1
        bcs.s   4f
        move.l  %d1,-(%sp)
        movem.l (%a0),%d0-%d7
        movem.l %d0-%d7,(%a1)
        move.l  (%sp)+,%d1
        lea     32(%a0),%a0
        lea     32(%a1),%a1
        moveq   #32,%d0
        sub.l   %d0,%d1
        bra.s   2b
4:      tst.l   %d1
        beq.s   1b
5:      move.l  (%a0)+,(%a1)+
        subq.l  #4,%d1
        bne.s   5b
        bra.s   1b
9:      rts

        .align  2
lean_chunks:
        .long   snap0, 512
        .long   snap1, 264
        .long   snap2, 248
        .long   snap3, 120
        .long   0, 0

        .if     512 + 264 + 248 + 120 - WORK_LEN
        .error  "0024-lean: the caves must hold WORK_LEN bytes"
        .endif

        .align  2
lean_par: .long 0                                 | 1 on a computing block
        .endif

        .if     P_HALF
        .section .snap0,"aw"
snap0:  .space  512
        .section .snap1,"aw"
snap1:  .space  264
        .section .snap2,"aw"
snap2:  .space  248
        .section .snap3,"aw"
snap3:  .space  120
        .text
        .endif

        .if     P_HALF == 0
        | cut alone needs no code; keep the section non-empty for the claim.
        .align  2
lean_none: .long 0
        .endif
