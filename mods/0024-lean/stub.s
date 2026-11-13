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
        .equ    SNAP,           0x4B680000        | the copy, in 0022's SDRAM

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
        lea     SNAP,%a0
        lea     WORK,%a1
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
        lea     WORK,%a0
        lea     SNAP,%a1
        bsr.s   lean_copy
        movem.l (%sp),%d0-%d7/%a0-%a5
        lea     56(%sp),%sp
9:      move.l  #SNAP_D7,%d7                      | displaced
        jmp     SNAP_RESUME

        | lean_copy(a0 from, a1 to): WORK_LEN bytes, 48 at a time, then 40.
        | Uses d0-d7, a0-a5.
        .align  2
lean_copy:
        lea     WORK_LEN-40(%a0),%a2
        move.l  %a2,%d0
        move.l  %d0,lean_end
1:      movem.l (%a0),%d0-%d7/%a2-%a5
        movem.l %d0-%d7/%a2-%a5,(%a1)
        lea     48(%a0),%a0
        lea     48(%a1),%a1
        cmpa.l  lean_end,%a0
        bne.s   1b
        movem.l (%a0),%d0-%d7/%a2-%a3
        movem.l %d0-%d7/%a2-%a3,(%a1)
        rts

        .if     (WORK_LEN - 40) % 48
        .error  "0024-lean: the copy's 48-byte steps must end 40 bytes short"
        .endif

        .align  2
lean_par: .long 0                                 | 1 on a computing block
lean_end: .long 0
        .endif

        .if     P_HALF == 0
        | cut alone needs no code; keep the section non-empty for the claim.
        .align  2
lean_none: .long 0
        .endif
