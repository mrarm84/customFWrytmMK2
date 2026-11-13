"""dgbench.py - run mod 0021's DG machines from a built MAIN OS image in an
emulator (Unicorn's ColdFire V4e), the way the audio interrupt calls them:
fn(voice, ctrl, params, pitch) once a block of 32 frames.

    dgbench.py bench  IMAGE ELF [--blocks N]           instructions and cycle estimate a block
    dgbench.py render IMAGE ELF OUTDIR [--seconds S]   one WAV per scenario (48 kHz, 16-bit)
    dgbench.py diff   DIR_A DIR_B                      compares two render outputs

IMAGE is build/mainos_<tag>.bin, ELF build/obj/0021-dg-machines.elf (its
symbols give each machine's entry). The cycle figure weights each executed
instruction by a rough ColdFire V4e cost (see COST); it is an estimate to
compare two builds with, not a unit's CPU reading. Needs `pip install unicorn`.
"""
import re, struct, subprocess, sys, wave, os, json
from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_CODE
from unicorn.m68k_const import UC_M68K_REG_A7, UC_M68K_REG_PC, UC_CPU_M68K_CFV4E

BASE = 0x40000400
WAVE_BUF, MSTATE, EXT_STATE = 0x80006bf8, 0x8000fef8, 0x4B600000
SMP_TAB, SMP_ADDR, SMP_LEN = 0x41329e70, 0x4F000000, 48000     # 1 s, 16-bit


def test_sample():
    """1 s of a voice-like test sample, 16-bit big-endian: a 110 Hz pulse
    train through two formants sweeping from "ah" to "ee", in three
    syllables, so grains of it are recognisable."""
    import math
    out = bytearray()
    ph = 0.0
    for i in range(SMP_LEN):
        t = i / 48000
        f1 = 700 - 400 * t                     # 700 -> 300 Hz
        f2 = 1200 + 1100 * t                   # 1200 -> 2300 Hz
        env = max(0.0, math.sin(math.pi * ((t * 3) % 1)))   # three syllables
        ph += 110 / 48000
        s = sum(math.sin(2 * math.pi * h * ph) / h *
                (math.exp(-((h * 110 - f1) / 120) ** 2)
                 + 0.6 * math.exp(-((h * 110 - f2) / 200) ** 2))
                for h in range(1, 30))
        out += struct.pack(">h", int(max(-1.0, min(1.0, 1.8 * s * env)) * 30000))
    return bytes(out)
VOICE_RESET = 0x4011e456
STACK_TOP = 0x90010000
RET_MAGIC = 0x90020000
FRAMES, RATE = 32, 48000
CPU_HZ = 266_000_000
BUDGET = CPU_HZ * FRAMES // RATE        # cycles in one block at 266 MHz
OBJDUMP = "m68k-elf-objdump"

MACHINES = ["dg_sine", "dg_saw", "dg_pulse", "dg_fm2", "dg_organ",
            "dg_chord", "dg_super", "dg_pluck", "dg_chip", "dg_fold", "dg_grain", "dg_wave"]


def k(v):
    """a knob 0..127 as the 8.8 word the machine reads"""
    return v << 8


# Scenarios: params in sound index order 9..16 (LEV TUN DEC FIN + four).
# "busy" turns on every optional pass a machine has (DRV, SUB, NOI, ...), the
# worst case; "plain" is the machine at its defaults with DEC held.
SCEN = {
    "dg_sine":  {"plain": [100, 64, 127, 64, 0, 0, 0, 0],
                 "busy":  [100, 64, 127, 64, 60, 40, 80, 70]},
    "dg_saw":   {"plain": [100, 64, 127, 64, 0, 0, 0, 0],
                 "busy":  [100, 64, 127, 64, 80, 60, 70, 60]},
    "dg_pulse": {"plain": [100, 64, 127, 64, 64, 0, 0, 0],
                 "busy":  [100, 64, 127, 64, 40, 80, 90, 60]},
    "dg_fm2":   {"plain": [100, 64, 127, 64, 3, 60, 127, 0],
                 "busy":  [100, 64, 127, 64, 5, 90, 90, 70]},
    "dg_organ": {"plain": [100, 64, 127, 64, 127, 127, 0, 0],
                 "busy":  [100, 64, 127, 64, 127, 127, 100, 90]},
    "dg_chord": {"plain": [100, 64, 127, 64, 0, 0, 0, 0],
                 "busy":  [100, 64, 127, 64, 5, 2, 90, 70]},
    "dg_super": {"plain": [100, 64, 127, 64, 60, 64, 0, 0],
                 "busy":  [100, 64, 127, 64, 100, 90, 70, 60]},
    "dg_pluck": {"plain": [100, 52, 100, 64, 90, 0, 64, 0],
                 "busy":  [100, 52, 100, 64, 70, 40, 90, 60]},
    "dg_fold":  {"plain": [100, 64, 127, 64, 0, 64, 0, 0],
                 "mid":   [100, 64, 127, 64, 64, 64, 0, 0],
                 "busy":  [100, 64, 127, 64, 100, 90, 80, 60]},
    # GRAIN: POS SIZ DEN SPR, then SMP (slot 1, the test sample; 0 the sine)
    "dg_grain": {"plain": [100, 64, 127, 64, 0, 48, 48, 16, 0],
                 "smp":   [100, 64, 127, 64, 32, 48, 48, 16, 1],
                 "cloud": [100, 64, 127, 64, 64, 90, 110, 80, 1]},
    # WAVE: WAV WEN WDC SUB, then SMP
    "dg_wave":  {"plain": [100, 64, 127, 64, 64, 0, 80, 0, 0],
                 "sweep": [100, 64, 127, 64, 0, 127, 70, 0, 0],
                 "smp":   [100, 64, 127, 64, 40, 60, 60, 0, 1]},
    "dg_chip":  {"plain": [100, 64, 127, 64, 2, 0, 0, 64],
                 "busy":  [100, 64, 110, 64, 1, 3, 100, 70]},
}
# A decaying note: DEC 20 (dies in well under the 3 s warm-up), the case
# where a voice goes quiet while the machine stays selected.
DECAY = 20
VOICES = 8          # the MKII's physical voices

# rough V4e costs, by mnemonic prefix; anything else 1
COST = [("divu.l", 20), ("divs.l", 20), ("divu.w", 10), ("divs.w", 10),
        ("remu", 20), ("rems", 20),
        ("muls.l", 4), ("mulu.l", 4), ("muls.w", 2), ("mulu.w", 2), ("muls", 4), ("mulu", 4),
        ("movem", 0), ("bsr", 3), ("jsr", 3), ("rts", 3), ("jmp", 2),
        ("lea", 1)]


class Image:
    def __init__(self, image, elf):
        self.code = open(image, "rb").read()
        nm = subprocess.check_output(["m68k-elf-nm", elf]).decode()
        self.sym = {p[2]: int(p[0], 16) for p in (l.split() for l in nm.split("\n")) if len(p) == 3}
        self.cost = {}
        dis = subprocess.check_output([OBJDUMP, "-d", "--no-show-raw-insn", elf]).decode()
        for l in dis.split("\n"):
            m = re.match(r"^([0-9a-f]+):\s+(\S+)\s*(.*)$", l.strip())
            if not m:
                continue
            a, mn, ops = int(m.group(1), 16), m.group(2), m.group(3)
            c = 1
            for p, w in COST:
                if mn.startswith(p):
                    c = w
                    break
            if mn.startswith("movem"):
                c = 1 + bin(int(re.search(r"#?(0x[0-9a-f]+|\d+)", ops).group(1), 0)).count("1") \
                    if re.match(r"#", ops) else 1 + _movem_regs(ops)
            # a memory operand costs a cycle more (operand cache hit)
            if "@" in ops or "(" in ops:
                c += 1
            self.cost[a] = c


def _movem_regs(ops):
    n = 0
    for part in re.findall(r"%[ad]\d(?:-%[ad]\d)?", ops):
        r = re.findall(r"%([ad])(\d)", part)
        if len(r) == 2:
            (k0, i0), (k1, i1) = r
            n += (8 * (k1 == "a") + int(i1)) - (8 * (k0 == "a") + int(i0)) + 1
        else:
            n += 1
    return n


class Machine:
    def __init__(self, img, count=False):
        self.img = img
        uc = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
        uc.ctl_set_cpu_model(UC_CPU_M68K_CFV4E)
        uc.mem_map(0x40000000, 0x400000)
        uc.mem_write(BASE, img.code)
        uc.mem_write(VOICE_RESET, b"\x4e\x75")             # rts: no circuit here
        uc.mem_map(0x41900000, 0x200000)                    # param_info
        uc.mem_map(0x80000000, 0x20000)                     # SRAM
        uc.mem_map(EXT_STATE, 0x100000)                     # SDRAM 0022 freed
        uc.mem_map(0x90000000, 0x30000)                     # stack, return
        uc.mem_map(0xfc070000, 0x1000)                      # DMA timer 0 (reads 0)
        # the sample slot table and a test sample in slot 1, for DG GRAIN
        uc.mem_map(0x41300000, 0x100000)
        uc.mem_map(SMP_ADDR, 0x100000)
        uc.mem_write(SMP_ADDR, test_sample())
        uc.mem_write(SMP_TAB + 16, struct.pack(">IIII", SMP_ADDR, 48000, SMP_LEN, 0x40000000))
        uc.mem_write(RET_MAGIC, b"\x4e\x71\x4e\x71")
        self.uc = uc
        self.n = 0
        self.cyc = 0
        if count:
            cost = img.cost
            self.prof = {}
            def hook(uc, addr, size, _):
                self.n += 1
                c = cost.get(addr, 1)
                self.cyc += c
                self.prof[addr] = self.prof.get(addr, 0) + c
            uc.hook_add(UC_HOOK_CODE, hook)

    def warm(self, fn, params):
        """runs voice 7 until any one-time set-up (0021 lite's sine table,
        built over several calls) is done, so voice 0's notes start on time"""
        for _ in range(16):
            self.block(fn, 7, params)

    def trig(self, v):
        self.uc.mem_write(MSTATE + 32 * v, b"\0" * 8)

    def block(self, fn, v, params, pitch=60 << 16):
        uc = self.uc
        p = 0x90018000 + 32 * v
        uc.mem_write(p, struct.pack(">8h", *[k(x) for x in params[:8]]))
        smp = params[8] if len(params) > 8 else 0          # sound index 19, SMP
        uc.mem_write(p + 20, struct.pack(">h", k(smp)))
        sp = STACK_TOP - 64
        uc.mem_write(sp, struct.pack(">5I", RET_MAGIC, v, 0x800063c0, p, pitch & 0xffffffff))
        uc.reg_write(UC_M68K_REG_A7, sp)
        uc.emu_start(self.img.sym[fn], RET_MAGIC, count=2_000_000)
        return struct.unpack(">32i", uc.mem_read(WAVE_BUF + 128 * v, 128))


def bench(image, elf, blocks=64):
    img = Image(image, elf)
    out = {}
    for fn in MACHINES:
        for name, params in list(SCEN[fn].items()) + [("decayed", None)]:
            m = Machine(img, count=True)
            pr = params if params else SCEN[fn]["plain"][:2] + [DECAY] + SCEN[fn]["plain"][3:]
            m.trig(0)
            warm = 3 * 48000 // 32 if name == "decayed" else 24     # 3 s: the note has died
            mm = Machine(img) if name == "decayed" else None
            if mm:   # run the warm-up uncounted, then carry the state over
                mm.warm(fn, pr)
                mm.trig(0)
                for _ in range(warm):
                    mm.block(fn, 0, pr)
                for base, size in ((0x80000000, 0x20000), (EXT_STATE, 0x100000)):
                    m.uc.mem_write(base, bytes(mm.uc.mem_read(base, size)))
            else:
                for _ in range(warm):
                    m.block(fn, 0, pr)
            m.n = m.cyc = 0
            m.prof = {}
            for _ in range(blocks):
                m.block(fn, 0, pr)
            out[f"{fn}/{name}"] = (m.n / blocks, m.cyc / blocks)
            if PROFILE and name == "busy":
                syms = sorted((a, s) for s, a in img.sym.items() if not s.startswith("txt_"))
                by = {}
                for a, c in m.prof.items():
                    s = max((x for x in syms if x[0] <= a), default=(0, "?"))[1]
                    by[s] = by.get(s, 0) + c / blocks
                print(fn, " ".join(f"{s}={c:.0f}" for s, c in sorted(by.items(), key=lambda x: -x[1])[:8]))
        # after boot: the worst block while any one-time set-up runs, all
        # eight voices on this machine from the first block
        m = Machine(img, count=True)
        worst = 0
        for _ in range(16):
            m.n = 0
            for v in range(VOICES):
                m.trig(v)
                m.block(fn, v, SCEN[fn]["plain"])
            worst = max(worst, m.n)
        out[f"{fn}/boot-worst"] = (worst / VOICES, 0)
    return out


PROFILE = "--profile" in sys.argv


def render(image, elf, outdir, seconds=2.0):
    img = Image(image, elf)
    os.makedirs(outdir, exist_ok=True)
    nblk = int(seconds * RATE / FRAMES)
    for fn in MACHINES:
        for name, params in SCEN[fn].items():
            for pitch in (48, 60, 72):
                m = Machine(img)
                m.warm(fn, params)
                m.trig(0)
                pcm = []
                for b in range(nblk):
                    if b == nblk // 2:
                        m.trig(0)                       # a second trig halfway
                    pr = list(params)
                    pcm.extend(m.block(fn, 0, pr, pitch << 16))
                path = os.path.join(outdir, f"{fn}_{name}_{pitch}.wav")
                with wave.open(path, "wb") as w:
                    w.setnchannels(1)
                    w.setsampwidth(2)
                    w.setframerate(RATE)
                    w.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, s >> 16))) for s in pcm))
                with open(path[:-4] + ".raw32", "wb") as f:
                    f.write(struct.pack(f">{len(pcm)}i", *pcm))


def diff(a, b):
    import numpy as np
    rows = []
    for f in sorted(os.listdir(a)):
        if not f.endswith(".raw32"):
            continue
        x = np.frombuffer(open(os.path.join(a, f), "rb").read(), ">i4").astype(np.float64)
        y = np.frombuffer(open(os.path.join(b, f), "rb").read(), ">i4").astype(np.float64)
        n = min(len(x), len(y))
        x, y = x[:n], y[:n]
        sig = np.sqrt(np.mean(x * x)) + 1e-9
        err = np.sqrt(np.mean((x - y) ** 2))
        db = 20 * np.log10(err / sig) if err > 0 else -999
        rows.append((f[:-6], sig / 2**31, db, np.max(np.abs(x - y)) / 2**31))
    for r in rows:
        print(f"{r[0]:28s} rms {r[1]:.3f}  diff {r[2]:7.1f} dB  max {r[3]:.4f}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "bench":
        blocks = int(sys.argv[sys.argv.index("--blocks") + 1]) if "--blocks" in sys.argv else 64
        r = bench(sys.argv[2], sys.argv[3], blocks)
        if "--json" in sys.argv:
            print(json.dumps(r))
        else:
            for kk, (n, c) in r.items():
                if kk.endswith("boot-worst"):
                    print(f"{kk:22s} {n * VOICES:8.0f} instr in the worst block, all {VOICES} voices")
                    continue
                print(f"{kk:22s} {n:8.0f} instr  {c:8.0f} cyc  {VOICES} voices {100 * VOICES * c / BUDGET:5.1f}% of a block")
    elif cmd == "render":
        s = float(sys.argv[sys.argv.index("--seconds") + 1]) if "--seconds" in sys.argv else 2.0
        render(sys.argv[2], sys.argv[3], sys.argv[4], s)
    elif cmd == "diff":
        diff(sys.argv[2], sys.argv[3])
