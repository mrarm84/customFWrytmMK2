
# rytm-mods (lite)

**Branch `lite` of rytm2_second.** The whole of rytm-mods-src as of 2026-11-13
(2c6040a and its uncommitted working tree), with mod 0021's DG machines
rewritten to cost far less of the audio interrupt. Same nine machines, same
knobs, records, slots and sound (see below); the other mods are unchanged.

| DG machine, 8 voices | before, plain / busy | lite, plain / busy | a voice whose note has died |
|---|---|---|---|
| SINE  | 12.4% / 25.6% | 5.2% / 12.5% | 12.6% -> 1.0% |
| SAW   |  9.4% / 30.6% | 5.3% / 16.9% |  9.6% -> 1.0% |
| PULSE | 12.8% / 20.8% | 7.2% / 10.1% | 13.0% -> 1.0% |
| FM2   | 20.2% / 20.4% | 7.9% /  8.1% | 20.4% -> 1.0% |
| ORGAN | 35.1% / 35.1% | 11.7% / 11.7% | 35.3% -> 1.0% |
| CHORD | 26.1% / 32.2% | 11.9% / 16.4% | 26.2% -> 1.0% |
| SUPER | 39.3% / 53.3% | 18.3% / 25.5% | 39.5% -> 1.0% |
| PLUCK | 19.3% / 27.5% | 13.0% / 17.4% | 18.0% -> 1.0% |
| CHIP  | 12.4% / 12.8% | 6.9% /  7.4% | 12.6% -> 1.0% |

Share of one 32-frame audio block (0.67 ms at 266 MHz) the machine takes with
all 8 voices on it, from `tools/dgbench.py`: the built image run in an emulator
(Unicorn's ColdFire V4e) as the interrupt calls it, each instruction weighted
by a rough V4e cost. An estimate for comparing builds, not a reading from a
unit. "plain" is the machine at its defaults, "busy" with every optional pass
on (DRV, SUB, NOI ...); "died" is DEC 20 after the note has faded.

How (details in `mods/0021-dg-machines/stub.s`'s header):

- sines from a 4096-point table in the SDRAM 0022 freed, built from the old
  polynomial in a few blocks after boot (machines silent until it is done);
- a polyBLEP saw whose wrap is the phase add's overflow, the correction only
  at the two samples around each wrap, and no call inside any sample loop;
- DG PLUCK reuses each sample's filter output and string taps in the next;
- a voice whose DG envelope has died (DEC 0..100, or 127 after it reached
  zero), or whose string has rung out, only clears its buffer until the next
  trig. **With DEC 127 (hold, the default) the AMP envelope ends the note in
  the voice hardware, which the CPU cannot see, so such a voice keeps
  computing after it is inaudible.** Setting DEC to roughly the AMP decay lets
  a voice go idle when its note ends.

Same sound, checked by rendering every machine at C3, C4 and C5, plain and busy,
with a retrig, from both images (`dgbench.py render` / `diff`): CHORD, PLUCK,
SAW and SUPER at their defaults are bit-identical; the saw and pulse family
otherwise differ by rounding, -63 to -110 dB; SINE, ORGAN and FM2 by the
table's phase step, -50 to -61 dB, with the same worst harmonic and spur levels
as before (the old polynomial's own error is that large).

    pip install unicorn numpy            # once, in a Linux or WSL Python
    python3 tools/dgbench.py bench  build/mainos_<tag>.bin build/obj/0021-dg-machines.elf
    python3 tools/dgbench.py render build/mainos_<tag>.bin build/obj/0021-dg-machines.elf OUT/
    python3 tools/dgbench.py diff   OUT_A/ OUT_B/

**0013, DAC SUM only.** The per-track DAC FILTER, transient shaper and POL are
out of the audio interrupt and their page is hidden; the filter on the voices is
0019's DIST filter, on the sum. The sum is rytm2_mods' voice-dac 1.7 (pan split
cached per voice, two frames per pass over four accumulators, no multiplies with
no voice on the bus). The unit read 2.44% of a block for DAC SUM with every
filter off, 4.24% with LP1 on every track, and 100% CPU with one LP2 (rytm2_mods,
2026-11-08); lite runs none of the filters, and a static count puts the sum at
about 1,100 instructions a block against about 1,500 for the old path with
every filter off. Not measurable in the emulator (Unicorn mis-decodes `msac`
with a load), not yet run on a unit.

**REVERB 2 and degrade.** The comb (CMB, CMK) and the octaver are out; REVERB 2
is WID SRR HIS 12B / DRK SAT TRM RNG: stereo width, darken (a lowpass),
saturation and auto-pan, each nothing at 0 and about 1,300..2,000 instructions a
block on (emulator). The phaser moved to cave21 to make room. DEGRADE on LFO RND's
G and H (SRD downsample, BIT bit depth), per sound, in 0013's FRQ and DEP fields:
with DAC SUM off only degraded tracks' voices leave the analog bus. The idle
tick refreshes the per-track values every fourth tick.

**Portamento.** GLD (OFF/ON, default OFF) and TIM, per sound; first on LFO RND's
page (0004, knobs C and D), now on the TRIG page (see Trig locks below). A detour at the audio interrupt's machine call
(0x401211ce) glides each voice's pitch argument toward the played note,
exponentially in semitones, tau = 1 ms * 2^(TIM / 12); every machine takes its
pitch from that argument, so analog and DG machines alike glide. Stored in 0013's
POL and RES fields, which lite no longer uses. The stub was run in the emulator
against the built image (pitch per block, registers kept); not yet on a unit.

**Trig locks (branch `lite-triglock`, 2026-11-17).** GLD and TIM moved to the
TRIG page (knobs E and F, where SYN and SMP were) and can be locked per step;
SYN and SMP moved to LFO RND's C and D. The TRIG page's TrigParameterSet only
knows locks for its own ids, so 0013 patches its lock read/write/clear slots: a
GLD or TIM lock is one marked word on sound index 0 of the step's locks (the
sound's free word, 0004's), and a hook in trig_fire, where the step's lock row
is handed on (0x4009af84), keeps it per track for porta. On LFO RND, SYN and SMP
reach the track's TrigParameterSet through wrappers in the SoundParameterSet's
vtable. DS1/DP1/DS2/DP2 are no longer lockable: the page views' lockable test
(0x4003788a) let them write stock's raw value as a lock on sound index 0, which
showed lit and read ERR. Three caves from the cavescan surplus (cave36..38). The
stubs were run in Unicorn against the built image with the stock functions they
call faked (123 checks: lock encoding, stack and registers, the routing, the
lockable test, the trig_fire capture and the glide); not yet on a unit.

Not yet run on a unit. The build is the same as below (`make verify`).

## Changes, 2026-11-17 and 18: trig locks and live loops

Two branches on top of the lite line (e66ea74), each commit with a build of its own.

**`lite-triglock`: portamento you can lock.**

- GLD and TIM are on the TRIG page, knobs E and F, and lock per step: hold a
  trig and turn. A locked GLD ON slides into that step's note only.
- SYN and SMP moved to LFO RND's knobs C and D, the same settings as before:
  the track's default, or a held trig's own switch. New patterns start with both
  ON, as stock.
- LFO RND's DS1, DS2, DP1 and DP2 can no longer be locked. Holding a trig and
  turning them used to write a broken lock, shown lit with ERR; clear such locks
  once.
- Details in the Trig locks paragraph above and in `docs/MANUAL.md` (0004, 0013).

**`lite-live`: four live loops (mod 0028).**

- Tracks 1, 2, 5 and 6 (BD, SD, BT, LT; one voice each, so all four play at once)
  are loopers on sample slots 124, 125, 126 and 127.
- Select the track and record with the stock recorder from any screen: SAMPLING
  + YES arms, starts and stops; SAMPLING + NO discards. SRC, THR and RLEN are the
  recorder's.
- The slot plays the take a few milliseconds after it starts, while it is still
  being written. STA, END and LOOP span the whole RLEN, so STA locks slice it, as
  on an Octatrack's pickup machine.
- The recorder's 33 s buffer is split in four: 8.25 s a loop (4 bars at 116 BPM
  or faster). Loop takes are not normalized; nothing is copied, about 40
  instructions a block.
- Not saved: power off and the loops are gone. A take on any other track records
  as stock, into the whole buffer, over the loops' audio.
- How: the stock recorder (0x4013f56c), its state (0x419f0330) and the sample
  slot table (0x41329e70, 16 bytes a slot) are traced in `re/symbols.toml`; the
  stub's header (`mods/0028-live-slot/stub.s`) lists each detour.

Both were checked in Unicorn against the built image, with the stock functions
they call faked: 123 checks for the trig locks, 42 for the loops. Neither has
been run on a unit.

**Each mod folder has a README** (`mods/NNNN-slug/README.md`) for browsing on
GitHub: status, what it does, how to use it, its files. They are generated from
`mod.toml` and `docs/MANUAL.md` by `python3 tools/mod_readmes.py`; rerun it after
editing either.

## Lite, 2026-11-13: CV trig, a leaner interrupt, PERF push, the meter

Branches on top of `lite` (9aa3b60), each a step that can be gone back to. Every
.syx built is a commit, filed in `../rytm_syx_builds` as
`NN_<branch>_<commit>_<what>.syx` with its hash in `SHA256.txt` there.

| build | branch | what |
|---|---|---|
| 13..15 | `lite-cvfix` | 0020 CV trig: one gate one trig, CTRL IN 1 -> T1, CTRL IN 2 -> T2, every CONTROL INPUT mode, no settings |
| 21 | `lite-lean` | + 0024 `cut`: performance locks and CV modulation out of the interrupt (~1.4%) |
| 25 | `lite-perfpush` | + 0025: PERF pads push their track (FRQ -5%, RES/DEL/REV +5%, a random slow LFO), pads orange |
| 12, 17..24 | | measuring builds with the 0023 meter; not for playing |

**0020 CV trig.** A rising gate above 1 V plays the track once; the note-off
follows 50 ms later (`len_ms`) whatever the gate's length, the falling edge
below 0.5 V only re-arms, and the port is not read for 2 ms after a trig. Both
ports use CTRL IN 1's millivolt conversion (CTRL IN 2's own never let a gate
through on the unit). An empty jack may ghost the other one, as the converter
takes AN1 and AN2 in turn; not seen on this build yet. Manual: `docs/MANUAL.md`.

**0024 lean.** `cut` (on): adc_pedal_update, the two CTRL IN MOD route calls
and the 48 performance locks are no longer run. `half` (off): parameter
smoothing and interpolation every other block, restoring the working array from
a copy in between. Measured on the unit it gained nothing, the copy costing
about 2.7% to restore and 2% to take wherever it lives outside on-chip SRAM, so
it is off until the copy can live in SRAM or a design needs none.

**0025 perf push.** In PERF a plain pad press edits pad N's track through the
sound set's delta handler, as knob turns: FRQ -6.4 steps, RES, DEL and REV
+6.4, and a random LFO with every knob in the first quarter of its range (SPD
1..16, the six slowest MUL, any WAV, FRE/TRG, SPH 0..31, FAD 0..16, DEP 1..32,
DST one of 0004's sixteen). Saved with the kit; RELOAD undoes it. Not yet run
on a unit.

**0023 meter and `tools/isr_meter.py`.** DMA timer 0 at the audio interrupt's
entry, exit and nineteen points between, streamed over USB channel 10 (USB
CONFIG OVERBRIDGE; on Windows the Overbridge driver's ASIO device, which the
script enables). `py tools/isr_meter.py [--seconds N | --live]`. Off by default:
build with `--mods ... 0023-isr-meter`. It needs 0024's `half` off (they share
caves).

**What the meter found** (build 23, CHORD + DAC SUM + DIST FILTER + REVERB 2
effects + delay and reverb, Overbridge connected): the interrupt at 96% median,
99.7% peak, sections summing to the whole:

| section | share |
|---|---|
| `0x4011c64c` + envelopes, pan/mute, master volume | 24.5% (not the sample layer: unchanged with every sample off) |
| stock delay + reverb | 18.9% |
| machines (CHORD) | 15-17% |
| entry, trigs, voice set-up | 8.5% |
| parameter smoothing + interpolation | 5.3% |
| DAC SUM | 4.7% |
| REVERB 2 / phaser / DIST FILTER | 4.4% |
| USB send (Overbridge, only while connected) | 3.9% |
| LFOs | 3.1% |

0013's burn test (2026-10-06) showed the UI lagging from +0.5% of added
interrupt load, so every percent counts. Build 24 splits the 24.5% section
further; not yet read.

**Memory and caching.** The data cache covers only 0x40000000..0x47ffffff
(ACR0 0x4007e020; CACR's default is cache-inhibited). 0022's SDRAM
(0x4B6.., 0x4B7..), where 0021's sine table and pluck buffers and 0019's chorus
live, and the sample memory (0x4F9..) are uncached. Overbridge, scenes and
performance cost nothing in the interrupt when unused beyond what 0024 cuts;
removing them would free code space, not CPU.

**Next: new DG machines.** Seven machines for the hidden slots 35..40, 42, 43
(each brings its old routine's ~1 KB as code room), sample-aware where it fits,
working as before with no sample: DG GRAIN (granular from the track's sample),
DG WAVE (wavetable; the sample becomes the table), DG MODAL (a Rings-like
resonator the sample excites), DG SUBTR (two oscillators and a resonant
lowpass; oscillator 2 the sample), DG FOLD (a wavefolder, folding the sample),
DG FORM (formants), and PLUCK's burst from the sample. A shared, unlockable
page 2 for every DG machine: SUB MIX ATK CRV / SAT DRK TRM RNG, stored in the
saved sound's last 8 spare bytes. First the groundwork: the sample table's
layout, and the DG tables moved from uncached SDRAM into the cached heap.

# rytm-mods

-Public copy of MrScruff's firmware modifications for the Analog Rytm MKII, redistributed with permission. Released as-is, responses to issues should not be expected.

Firmware modifications for the Elektron Analog Rytm MKII, OS 1.73.

Every build starts from the pinned stock image and rebuilds from source. The
`.syx` is an artifact; the patch sources, the symbol map and the allocation
registry are the project.

Same conventions as `octatrack-mods`, same registry and verification discipline,
different device. Nothing is shared between the two trees.

## Layout

| path | what |
|---|---|
| `stock/` | checksum of the pinned stock firmware, which you supply. Never written to. |
| `re/` | cumulative reverse-engineering knowledge: `symbols.toml`, subsystem notes, Ghidra bootstrap |
| `mods/NNNN-slug/` | one modification: manifest, stub source, design rationale |
| `requirements.txt` | Python packages for the mod 0006 and 0013 calibration and measurement tools |
| `registry/` | `allocations.toml` - every claim on cave space and detour sites |
| `tools/` | build, layout validation, verification, symbol generation, cave scan; capture off the device (`mix_capture.py`); mod 0013 measurement (`voice_dac_*.py`) |
| `vendor/` | third-party code that is **executed** (elektron-firmware-tool), fetched by `make setup` |
| `docs/` | user manual, flashing, hazards, calibration |
| `build/` | artifacts, gitignored |

## Build

Prerequisites:

- Python 3.11 or newer (build and verify use only the standard library)
- `git`, `make` and a C compiler, for the vendored container tool
- `m68k-elf-binutils` (`brew install m68k-elf-binutils` on macOS)
- a Ghidra install, only for `make ghidra`

The stock firmware is not included. Download Analog Rytm MKII OS 1.73 from
Elektron's support site and place the `.syx` at
`stock/Analog-Rytm_MKII_OS1.73.syx`. The build refuses any file whose checksum
differs from `stock/SHA256SUMS`.

    make setup     # venv + Python deps, clone and build the vendor tool at its pinned commit
    make verify    # build + assert the result

Produces `build/Analog-Rytm_MKII_OS1.73_<tag>.syx`, the only delivery format this
device has - there is no CF-card `.bin` equivalent. On branch `robust-live` the default build's tag is
`0000_0002_0004_0010_0013_0014_0015_0019_0020_0021_0022`. See `docs/FLASHING.md` to install it.

Build a subset for hardware bisection:

    .venv/bin/python tools/build.py --mods 0000-shared 0002-euclid-accents

## The container

Unpacks and repacks with the vendored tool, all checksums verified, five sections:

| id | name | size | load base | we touch it |
|---|---|---|---|---|
| 5 | meta | 15 B raw | - | no |
| 2 | bootstrap | 42,302 | 0x07020000 | **no** - see `docs/HAZARDS.md` |
| 1 | FPGA | 149,516 | 0x00000000 | no |
| 3 | MAIN OS | 3,005,432 | 0x40000400 | yes, this is the whole project |
| 8 | ? | 159,948 | 0x00000000 | no |

MAIN OS is ColdFire big-endian, as on the Octatrack, but it is a C++ build with its
Itanium-ABI symbol names left in (`ParameterPageView::changeParameterLockValue`,
`AnalogRytm::logicalParamID_t`, `Kit::updateMirror`). Most of the map can be recovered
by demangling rather than by guessing.

Section 8 is new in 1.73, little-endian ARM Thumb rather than ColdFire, and carries
`{"version": "1.00E", "release": "0018"}`. 1.73's only listed improvement is
"[MKII] Added Outbox 8 configuration support", so it is almost certainly the Outbox 8's
own firmware riding along - inferred, not proven.

`make verify` asserts that sections 5, 2, 1 and 8 come back out of our rebuilt `.syx`
byte-identical to stock, so a mistake can only ever reach MAIN OS.

## Mods

On `lite-live` the default build enables 0000, 0002, 0004, 0010, 0013, 0014,
0015, 0019, 0020, 0021, 0022, 0024, 0025, 0027 and 0028. 0023 and 0026 are
measuring builds, off by default. Retracted mods and one-off hardware probes are
not part of this package; the pool notes in `registry/allocations.toml` still
record what those probes established. Each mod's folder has a README.

| id | title | status |
|---|---|---|
| 0000 | The shared runtime other mods call into | built |
| 0002 | Euclidean generator places accents instead of trigs | hardware-verified |
| 0004 | Two per-sound random modifiers on a second LFO page (lite: SYN and SMP on it too) | built |
| 0010 | NO + PLAY toggles between the edited kit and the saved one | hardware-verified |
| 0013 | Voices to MAIN through the DAC (lite: DAC SUM only, degrade, portamento and its trig locks) | hardware-verified; the lite changes are not |
| 0014 | CTRL ALL: TRK + knob turns that parameter on every sound track | hardware-verified |
| 0015 | ENV RESET reaches AMP and AMP+FILT | hardware-verified |
| 0019 | Phaser on the REVERB page, REVERB 2, DIST filter | built |
| 0020 | CTRL IN and AUDIO IN trigger tracks | built |
| 0021 | New digital machines in the hidden slots (lite: the CPU-light rewrite) | built |
| 0022 | Delay ring halved to 2 MB, freeing 2 MB of RAM | built |
| 0023 | Audio interrupt load meter over USB (off by default) | built |
| 0024 | Lean interrupt: smoothing at half rate; perf locks and CV modulation out | built |
| 0025 | PERF pads push their track | built |
| 0026 | Data cache over the uncached SDRAM (off) | retracted |
| 0027 | The sample layer skips voices that would only make silence | built |
| 0028 | Live loops: tracks 1, 2, 5 and 6 record into slots 124..127 and play while recording | built |

Status ladder: `re-only` -> `built` -> `hardware-verified`, plus `retracted`.
Only `hardware-verified` counts.

## Adding a mod

1. Add any new addresses to `re/symbols.toml` with an honest `status`.
2. Claim cave space and detour sites in `registry/allocations.toml`, recording the
   stock bytes at each detour host in `expect`. A mod may hold several cave claims,
   each naming the `section` it holds (`.text` by default): the pools are separate
   regions of the image and can never merge, so anything larger than the biggest
   free run has to be split, and the split belongs in the registry rather than
   being implied by sizes.
3. Write `mods/NNNN-slug/{mod.toml,stub.s,design.md}`, then run
   `python3 tools/mod_readmes.py` for its README.
4. `make verify`, then flash that mod alone.

The `expect` bytes are the load-bearing guard: if an address is wrong or two mods
collide, the build aborts instead of quietly patching the wrong place.

Before the first mod ships, the cave pool has to be earned: `make cavescan` reports
the candidates, `registry/allocations.toml` explains why the current one was chosen,
and it stays `status = "candidate"` until it has been proven untouched at runtime on
hardware. octatrack-mods inherited a pool it had not checked and lost a round trip to
it.
