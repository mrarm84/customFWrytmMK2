        | Mod 0026 - data caching for the uncached SDRAM above 0x48000000.
        |
        | MAIN OS's start-up sets CACR (data cache on, default mode
        | cache-inhibited) and ACR0, which caches 0x40000000..0x47ffffff in
        | copyback mode, and leaves ACR1 unused. So 0x4B.. (the stock reverb's
        | buffers at 0x4B000000/0x4B090000, the delay ring at 0x4B400000, 0022's
        | free RAM with 0021's tables and 0019's chorus) and 0x4F.. (sample
        | memory) are uncached. This sets ACR1 in write-through mode, so memory
        | is always current and DMA reading it stays right:
        |   region 1  0x4B000000..0x4BFFFFFF
        |   region 2  0x48000000..0x4FFFFFFF
        | DMA writing into a cached range is the hazard: the CPU could read a
        | stale line. The one such writer found statically, eDMA 59 into
        | 0x4B827280, is pushed out of the cache by stock (cpushl dc) before each
        | transfer. The delay's eDMA 30 and 42 move its ring to and from SRAM;
        | the CPU does not read the ring itself.
        |
        | cache_acr1  detour 0x400008e8, start-up's `movel #0x4007e020,%d0`
        |             (ACR0's value), re-emitted after ACR1 is set; rejoins at
        |             the movec to ACR0.

        .if     P_REGION == 1
        .equ    ACR1_VAL,       0x4B00E000        | base 0x4B, mask 0, E, S both, write-through
        .elseif P_REGION == 2
        .equ    ACR1_VAL,       0x4807E000        | base 0x48, mask 7
        .else
        .error  "0026-cache: region must be 1 or 2"
        .endif
        .equ    ACR0_VAL,       0x4007e020
        .equ    RESUME,         0x400008ee        | movec %d0,%acr0

        .text
        .align  2
cache_acr1:
        move.l  #ACR1_VAL,%d0
        movec   %d0,%acr1
        move.l  #ACR0_VAL,%d0                     | displaced
        jmp     RESUME
