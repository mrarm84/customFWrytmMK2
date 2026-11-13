
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

Not yet run on a unit. The build is the same as below (`make verify`).

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

On `robust-live` the default build enables 0000, 0002, 0004, 0010, 0013, 0014,
0015, 0019, 0020, 0021 and 0022. Retracted mods and one-off hardware
probes are not part of this package; the pool notes in `registry/allocations.toml`
still record what those probes established.

| id | title | status |
|---|---|---|
| 0000 | The shared runtime other mods call into | built |
| 0002 | Euclidean generator places accents instead of trigs | hardware-verified |
| 0004 | Two per-sound random modifiers on a second LFO page | built |
| 0010 | NO + PLAY toggles between the edited kit and the saved one | hardware-verified |
| 0013 | Voices to MAIN through the DAC, with a per-sound filter | hardware-verified |
| 0014 | CTRL ALL: TRK + knob turns that parameter on every sound track | hardware-verified |
| 0015 | ENV RESET reaches AMP and AMP+FILT | hardware-verified |
| 0019 | SRR on the REVERB page with knob-press modes; DIST filter | built |
| 0020 | A gate into CTRL IN plays a track | built |
| 0021 | New digital machines in the hidden slots: DG SINE, SAW, PULSE, FM2, ORGAN, CHORD, SUPER, PLUCK, CHIP (lite: the CPU-light rewrite) | built |
| 0022 | Delay ring halved to 2 MB, freeing 2 MB of RAM | built |

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
3. Write `mods/NNNN-slug/{mod.toml,stub.s,design.md}`.
4. `make verify`, then flash that mod alone.

The `expect` bytes are the load-bearing guard: if an address is wrong or two mods
collide, the build aborts instead of quietly patching the wrong place.

Before the first mod ships, the cave pool has to be earned: `make cavescan` reports
the candidates, `registry/allocations.toml` explains why the current one was chosen,
and it stays `status = "candidate"` until it has been proven untouched at runtime on
hardware. octatrack-mods inherited a pool it had not checked and lost a round trip to
it.
