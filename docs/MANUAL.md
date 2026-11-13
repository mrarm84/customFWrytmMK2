# User manual

What each mod in the default build does on the device and how to use it. For
building see `README.md`, for installing see `docs/FLASHING.md`, and read
`docs/HAZARDS.md` before flashing.

The default image is
`Analog-Rytm_MKII_OS1.73_0000_0002_0004_0010_0013_0014_0015_0019_0020_0021_0022.syx` on branch
`clean` (0003, 0006, 0008, 0009, 0012, 0017 and 0018 are removed; they remain on
`robust-live-save-2026-11-12`). It is stock OS 1.73 with the mods below added; everything not mentioned here behaves as stock.

| mod | where | what |
|---|---|---|
| 0002 | TRIG > euclidean page, OP | euclid sets accents on your trigs instead of placing trigs |
| 0004 | LFO key, pressed twice | LFO RND page: two random modifiers per sound |
| 0010 | NO + PLAY | switch between the edited kit and the saved one |
| 0013 | AUDIO ROUTING > DAC SUM; FILTER key, pressed twice | voices summed through the DAC, with a per-sound filter, transient shaper and polarity |
| 0014 | TRK + any knob | turn that parameter on every sound track |
| 0015 | SOUND SETTINGS > ENV RESET | AMP and AMP+FILT: the amp envelope restarts on every trig |
| 0019 | FX track: REVERB page encoder G (turn, press), REVERB 2 page; DISTORTION page D/E/F; AUDIO ROUTING > DIST FILTER | phaser on the reverb or delay input; octaver, crusher, hiss, chorus, comb and ring mod on REVERB 2, each movable to the delay; a filter feeding the distortion |
| 0020 | none | a gate into CTRL IN 1 plays T1, into CTRL IN 2 plays T5 |
| 0022 | none | the delay's longest time is 5.33 s (was 8 s), freeing 2 MB of RAM for new effects and machines |
| 0021 | SYNTH page, machine DG SINE, DG SAW, DG PULSE, DG FM2 or DG ORGAN | new digital machines, chromatically tuned, on every track |

0000 is the shared code the others call into. It has no controls.

## 0002 - Euclidean accents

Normally the euclidean generator decides which steps play. With this mod it can
instead leave the pattern's trigs alone and mark some of them with ACCENT: the
grid says when, euclid says which hits are accented.

**Use.** On the euclidean page, the Bool Operator (OP) now has eight values instead
of four:

| value | icon | behaviour |
|---|---|---|
| OR, XOR, AND, SUB | stock gate glyph | stock euclidean |
| OR\*, XOR\*, AND\*, SUB\* | the same glyph with a dot, top right | accent mode, same operator |

In accent mode:

- Only steps with a trig in the grid play. Euclid adds nothing.
- A trig on a step where the euclidean pattern has a hit plays accented.
- Accents you set by hand stay; euclid only ever adds accent.
- Turning euclid off with FUNC held bakes the result: the accents are written
  into the pattern. Turning it off without FUNC leaves the pattern as it was,
  as stock does.

The setting is per track and survives save, power cycle and reload.

**On stock firmware** a pattern saved with an accent-mode track loads with euclid
off on that track.

## 0004 - LFO RND

A second LFO page with two random modifiers per sound. On every note trig each
modifier picks a random offset for its destination parameter and holds it until
the next note.

**Use.** Press the LFO page key a second time for LFO RND; press it again to
return to LFO.

| knob | label | setting |
|---|---|---|
| A | DS1 | modifier 1 destination |
| B | DS2 | modifier 2 destination |
| E | DP1 | modifier 1 depth |
| F | DP2 | modifier 2 depth |

A destination knob shows the parameter's short name instead of a dial. Turning it
opens the destination list, as LFO DST does. Pick with the knob, confirm with YES.
The list holds sixteen destinations:

- the eight machine parameters (SRC page), which follow the machine
- FIN, STA (sample)
- FRQ, RES (filter)
- DEC, PAN (amp)
- DEL, REV (sends)

A depth knob selects N from the same sixteen settings as 0003 (0 to 64). Each
note trig offsets the destination by a random amount between -N and +N, clamped
to the parameter's range. The offset is added on top of the parameter's value,
p-locks, slides and LFO 1. Depth 0 is off.

The four settings belong to the sound. They are saved with the kit and survive a
power cycle, and they travel with the sound through copy/paste and the sound
pool. Sounds made before the mod read the first destination at depth 0.

**Limitations**

- Voice tracks only; the FX track has no LFO RND.
- The four settings cannot be p-locked.
- After the sequencer stops, the last offsets stay applied until the next note.
  You may hear this on ringing notes and on pads.
- Pads get no randomisation until the pattern has played at least once.
- A step that plays a sound from the pool (sound lock) uses the kit sound's
  settings.
- A destination is stored as a machine slot. After a machine change it points at
  the same slot on the new machine; where that slot is empty the knob reads `--`
  and the empty slot does not appear in the list.

## 0010 - Kit A/B

Compare your edits to a kit against the saved version, and go back to your
edits.

**Use.** NO + PLAY, as for a stock reload.

| you press NO + PLAY when | it does | popup |
|---|---|---|
| you have edited the kit | keeps your edits aside and reloads the saved kit | KIT 1 RELOADED! |
| the saved kit plays, untouched since | brings your edits back | EDITS RESTORED! |
| the saved kit plays, but you have edited it | keeps those newer edits instead and reloads | KIT 1 RELOADED! |
| the kit has no edits | a plain reload, as stock | KIT 1 RELOADED! |

The number in KIT 1 RELOADED! is the current kit's, as stock shows it.

Only one set of edits is kept: editing the saved kit while comparing replaces the
edits kept aside. Changing to another kit, or any other reload, does the same.
The kit menu's reload behaves the same way; reloading all kits is stock.

**Limitations**

- The edits kept aside take 2.5 KB of the device's memory from the first press
  until power off.
- After EDITS RESTORED! the kit may not count as modified. Save explicitly.

## 0013 - DAC sum, filter and shaper

**Lite build: DAC SUM only.** The per-track DAC FILTER (FRQ, RES, TYP, DEP), the
transient shaper (ATK, SUS) and POL are removed from the audio path, and the DAC
FILTER page no longer opens: pressing FILTER again stays on the stock page. DAC
SUM itself works as below (GLOBAL > AUDIO ROUTING > DAC SUM). To filter the
voices digitally, use the DIST filter (0019) on the DISTORTION page, which acts
on the summed voices before the analog distortion, with its own on/off in AUDIO
ROUTING. The sum is voice-dac 1.7's faster one (pan split cached, two frames at a
time, nothing to multiply when no voice is on the bus). Values set on the DAC
FILTER page in an earlier build stay in the sounds but are ignored. Everything
below about the DAC FILTER page, the shaper and POL describes the full build.

Adds a filter, a transient shaper and a polarity switch to every voice, after
its analog filter, on a second FILTER page.
The Rytm's voices are analog all the way to the mix, so there is nowhere to put
a filter; with DAC SUM on, the voices leave the analog main bus and reach it
again through the DAC, processed on the way.

**DAC SUM.** In the GLOBAL menu, AUDIO ROUTING, the last item. ON routes every
voice to the main mix through the DAC; OFF is stock. The setting is kept with
the project, like the routing around it, and survives a power cycle.

With it on:

- level and pan are as through the analog path (within about 0.1 dB);
- the voices reach the mix about 2.6 ms later than through the analog path;
- ROUTE TO MAIN and track mutes work as usual;
- the delay and reverb sends, the compressor preview (0006), the sampler and
  the USB track channels all get the processed voice. The individual outputs
  do not: they carry the voice before the filter, shaper and polarity.

Switching DAC SUM clicks once.

**DAC FILTER.** With DAC SUM on, press FILTER a second time for the DAC FILTER
page. With DAC SUM off, pressing FILTER again stays on the stock page.

The top row is the filter:

| knob | values | |
|---|---|---|
| FRQ | 0..127 | the cutoff, on stock FRQ's scale: 13.8 Hz to 21.1 kHz, 440 Hz at 60 |
| RES | 0..127 | resonance, for the 2-pole types |
| TYP | OFF, LP2, LP1, BP, HP1, HP2, BS, PK | the filter type, in stock's order and shown as stock's glyph |
| DEP | 0.0dB, -0.3dB .. -31.5dB, FULL | how much of the voice goes through the filter |

- LP1 and HP1 are one-pole, 6 dB/oct, -3 dB at FRQ, with no resonance.
- LP2 and HP2 are two-pole, 12 dB/oct. RES raises a peak at FRQ, up to about
  +6 dB.
- BP is a band-pass, 0 dB at FRQ; BS a notch at FRQ; PK a peak at FRQ. For
  these RES narrows the band rather than adding a peak.

At FULL the voice is the filter's output alone. Below FULL the dry voice is
mixed back in, cutting by the amount DEP shows: HP1 and HP2 become low shelves,
LP1 and LP2 high shelves, BP cuts everything but the band, and BS becomes a bell
cut. 0.0dB is no filter at all. For PK, DEP is instead a boost at FRQ, +0.0dB
to +6.0dB.

The graph over FRQ and RES is stock's FILTER graph for the type, cutoff and
resonance; with TYP OFF it is a flat line. The FRQ popup reads as stock's FRQ
popup, in Hz where 0008 is installed. TYP and RES step as stock's knobs do.

The bottom row is the transient shaper and polarity:

| knob | values | |
|---|---|---|
| ATK | -64..+63 | the start of each hit: up to make it stand out, down to soften it |
| SUS | -64..+63 | what follows the start: up to bring the tail forward, down to tighten it |
| POL | +, - | the voice's polarity in the mix: - inverts it |

ATK and SUS at 0 leave the voice untouched; their dials show a dotted centre
there. At the ends they change a strong transient's attack or sustain by about
12 dB, with the total boost held to +6 dB. Quiet signal, below -60 dBFS, is
left alone. FUNC + turn jumps to the next of -64, 0 and +63. The shaper follows
the voice's level, so how much it acts depends on how sharp the sound's attack
is; a pad with no transient changes little.

POL is for lining up layered sounds, such as a kick and a bass on separate
tracks: turn one to - and listen for the low end filling in or thinning out.
It only changes the voice in the DAC sum.

The settings belong to the sound. They are saved and loaded with the sound and
the kit, and survive a power cycle with or without a kit save, as other kit
edits do. A sound that has never had them set
reads TYP OFF, FRQ 127, RES 0, DEP FULL, ATK 0, SUS 0, POL +.

Hold TRK while turning any of these knobs to change it on every voice track,
as 0014 does for stock's parameters.

**Known limits**

- Earlier versions of this mod stored DAC SUM over the TRACK 1 and TRACK 2
  MIDI channels. Projects saved with them load with DAC SUM off, TRACK 1
  CHANNEL 1 and TRACK 2 CHANNEL 1 or 2. Set the three again once.
- None of these settings can be p-locked, and they have no MIDI CC.
- Saving a sound or kit with stock firmware drops them (the sound reads TYP
  OFF, ATK and SUS 0, POL +).
- Sounds saved with an earlier version of this mod, which had only LP1 and HP1,
  load with a different type: LP1 reads as LP2 and HP1 as LP1. Set TYP again.
- Switching TYP between LP1 and HP1 clicks on sounds with a lot of low or high
  content; switching between other types can click too.
- A voice driven very hot can clip in the filter or the shaper.
- The mod takes about 2.4% of the audio processing time with DAC SUM on and
  every filter off, and about 0.4% more for each pair of voices on LP1 or HP1.
  The 2-pole types and the shaper cost time only for the voices using them;
  their cost has not been measured.

The design and the measurements are in `mods/0013-voice-dac/mod.toml`.

## 0014 - Control all

Hold TRK and turn a knob to change that parameter on all twelve sound tracks at
once.

**Use.** On a sound page (SYNTH, SAMPLE, FILTER, AMP, LFO) or the TRIG page,
hold TRK and turn a knob. Every track moves by the same amount, so differences
between them are kept: a track at 40 and one at 70 both go up by 10. Each track
stops at its own limits. The screen shows the selected track as usual.

On the SYNTH page the knob changes the same position on every track, whatever
machine each one has, within each machine's own range. A track whose machine
has no parameter in that position is left alone.

FILTER TYP is the exception: the selected track's type changes as usual and
every other track is set to the same type.

The turn changes the selected track only, as stock:

- with the FX track selected;
- while a trig key is held, so parameter locks stay on the selected track;
- for LFO DST, and for the parameters other mods add: the euclidean OP beyond
  SUB (0002), VEL's humanise amount (0003) and the LFO RND page (0004).

The DAC FILTER page (0013) works the same way: every voice track moves by the
same step, each within its own limits. TYP and POL are set the same on every
track: the type the selected track reaches, and the same polarity. FUNC + TRK + turn on ATK or SUS moves each track to its own next
stop of -64, 0 and +63.

The changes are ordinary edits: saved with the kit, undone by reloading it.

## 0015 - Amp envelope reset

On the analog machines a new trig does not restart the amp envelope: it carries
on from wherever the level is. With a long DEC the envelope never closes, so
AMP ATK is heard on the first hit and not after. This mod adds the amp to ENV
RESET, so the attack is heard on every hit.

**Use.** In the SOUND menu, SOUND SETTINGS, ENV RESET. The values are now OFF,
AMP, FILTER and AMP+FILT:

| value | amp envelope | filter envelope |
|---|---|---|
| OFF | continues | continues |
| AMP | restarts from silence | continues |
| FILTER | continues | restarts (stock) |
| AMP+FILT | restarts from silence | restarts (stock) |

The setting belongs to the sound: saved and loaded with it, as stock's FILTER
value is.

**Known limits**

- A trig on a voice that is still sounding drops it to silence at once, which
  can click, most with ATK 0 and a long DEC.
- On stock firmware AMP has no effect.

## 0019 - Reverb phaser, REVERB 2 and DIST filter

**PHS (REVERB page, encoder G)**

- The knob is the phaser **rate**: 0 is off, 1..127 runs from very slow
  (0.03 Hz) to fast (8 Hz).
- **Press** the encoder to cycle: `PH-` off, `PHS` on the reverb output,
  `PHS.` on the delay input (every repeat phased). It starts off: press once
  to hear it. The mode is device-wide and survives a power cycle.
- It acts only on the reverb (or delay) return, so the track needs some reverb
  (or delay) send to hear it.
- The rate is an ordinary FX parameter: saved with the kit and p-lockable.
  Kits that had an SRR value load it as a phaser rate.

**REVERB 2 page** (press the REVERB page key again)

| knob | what | 0 |
|---|---|---|
| A OCT | octaver: adds a sub-octave (an octave down), level | off |
| B SRR | sample-rate reduction, N holds each sample N + 1 times | off |
| C HIS | hiss, quiet: up to about -42 dB | off |
| D 12B | 12-bit FX: above 0, the reverb's output and the delay's input keep only their top 12 bits (no dither) | off |
| E | (empty) | |
| F CMB | comb filter tune, low to high | off |
| G CMK | comb feedback (how strong the comb is) | - |
| H RNG | ring modulator frequency, 20 Hz..4.8 kHz | off |

- **Press any REVERB 2 knob** to move its effect between the reverb output and
  the delay input. On the delay input every repeat goes through it (and the
  delay's send into the reverb too). A trailing dot on the label (`OCT.`,
  `SRR.` ...) means the effect is on the delay. CMB and CMK move the comb
  together. Device-wide, kept over a power cycle.
- **FUNC + hold** on SRR crushes the whole output while held (`ALL`).
- None of them can be p-locked; all are saved with the kit. Older kits load
  them off (CMK at 64).
- Each effect costs CPU only while its knob is above 0.
- BIT (bit reduction) is gone: its knob never turned properly. OCT took its
  place. The chorus is gone too: it cost too much CPU (playing slowed down).

**PANIC.** Stock's all-sound-off (pressing STOP twice, or MIDI CC 120) now also
fades the whole output out over 1 ms, keeps it silent for 40 ms while it clears
the delay's memory and resets these effects, then fades back in over 1 ms. Not
yet run on hardware; that STOP twice reaches it is assumed, not checked.
- Built 2026-11-13. 12B run on hardware 2026-11-13 ("it works"); the rest not yet.

**DIST filter (DISTORTION page, encoders D, E, F: FRQ, RES, TYP)**

- TYP is OFF, LP2, BP, HP2 or BS. FRQ uses stock's FRQ scale; RES sets Q.
- The distortion and compressor are analog, so the filter acts on the digital signal *before* the distortion: every voice when DAC SUM is on, plus PRE-routed FX returns. With DAC SUM off it only affects the PRE returns.
- The three values are saved with the kit and can be p-locked.
- SETTINGS > AUDIO ROUTING > DIST FILTER ON/OFF turns it off device-wide.

## 0020 - CV trig

A gate or trigger into a CTRL IN jack plays a track, as a pad does. There is
nothing to set up:

- **CTRL IN 1 plays T1** (pad 1, BD). **CTRL IN 2 plays T5** (pad 5, BT).
- It works in any CONTROL INPUT mode.
- The gate goes **on** above **1.0 V**: the track plays at its own pitch,
  velocity 127. It goes **off** below **0.5 V**, which sends the note-off, so on
  sounds that hold until note-off (AMP HLD 0) the gate's length is the note's.
- Any gate or trigger of about 1 ms or longer and over 1 V works (5 V and 10 V
  modular gates included). The gap between the two thresholds keeps a noisy
  signal from triggering twice.
- CONTROL IN 1 MOD and 2 MOD keep working, so one gate can trigger a sound and
  modulate it.

**Known limits**

- Velocity is always 127.
- A pedal plugged into a jack in EXPR mode triggers its track when pushed past
  1 V.
- Whether the notes are recorded in live recording or sent out on MIDI follows
  what stock does for Overbridge notes; not checked.
- Not yet run on hardware.

## 0021 - DG machines

New digital machines in the slots of the hidden test machines: DG SINE, DG SAW,
DG PULSE, DG FM2, DG ORGAN, DG CHORD, DG SUPER, DG PLUCK and DG CHIP.

**Use.** On any track, pick a DG machine as the machine. They come after the
stock machines in the list and run on every track, BD to CB. They are digital:
the analog circuit stays silent and the machine's output goes through the
track's FILTER and AMP, so those pages shape it as they shape UT NOISE.

**Shared knobs.**

- **TUN** 0..127 in semitones, 64 the base. At the track's own pitch, TUN 64 is
  C4 (261.63 Hz, A4 = 440 Hz). Notes played chromatically move it by semitones.
- **FIN** fine tuning, 64 is in tune, each step a cent.
- The pitch is computed exactly, to within 1 cent everywhere; the lowest note is
  C-1 (8.2 Hz) and the highest G9 (12.5 kHz).
- **DEC** 127, the default, holds the sound, so the AMP envelope shapes the note.
  0..100 add a decay of their own, from very short at 0 to about 30 s at 100.
  **101..126 loop**: the decay starts again each time it has faded, a pulse
  every 11 ms at 101 (a buzzing tremolo) to about 1 s at 126 (a slow gate).
  DG PLUCK's DEC is the string's and does not loop. Sounds saved with an older
  build with DEC above 100 now loop; turn DEC down to get the decay back.
- **LEV** the level.

**CPU (lite build).** A DG voice stops costing CPU once its own DEC decay has
faded out (DEC 0..100), or once DG PLUCK's string has rung out; it starts again
on the next trig. With DEC 127 the AMP envelope ends the note in the analog
voice, which the machine cannot see, so the voice keeps computing until the
track plays something else. On a busy pattern, set DEC to about the AMP decay
on DG tracks you don't need to hold. Right after power-on the DG machines are
silent for a few milliseconds while their sine table is built.

**DG SINE** (TUN FIN SWD DEC / SWT DRV SUB LEV)

- A pure sine, starting at phase 0 on every trig.
- **SWD** a pitch sweep down onto the note, up to +63 semitones above it at the
  trig; **SWT** how fast it falls. For 808-style kicks and toms: SWD 20..40.
- **DRV** a soft-clip drive, 0 off.
- **SUB** a sine an octave below, following the sweep; 127 is half and half.

**DG SAW** (TUN FIN DET DEC / SUB DRV NOI LEV)

- A band-limited saw (no aliasing whine at high notes).
- **DET** adds a second saw up to 50 cents sharp; 0 leaves one saw.
- **SUB** mixes in a sine an octave below; 127 is half and half.
- **DRV** a soft-clip drive, as DG SINE's; 0 off.
- **NOI** adds white noise, for breath or grit; 0 off.

**DG PULSE** (TUN FIN PW DEC / PWD PWR SUB LEV)

- A band-limited pulse. **PW** its width, 64 a square, thinner either way.
- **PWD** how far a triangle LFO sweeps the width (PWM), **PWR** its rate, from
  very slow at 0 to about 12 Hz at 127. The LFO restarts on every trig.
- **SUB** as DG SAW's.

**DG FM2** (TUN FIN RAT DEC / FMA FMD FB LEV)

- Two-operator FM: a sine carrier at the note, modulated by a second sine.
- **RAT** 0..15 picks the modulator's ratio to the note: 1/2, 1, 3/2, 2, 5/2,
  3, 7/2, 4, 5, 6, 7, 8, 9, 10, 12, 16. Whole ratios stay harmonic (tuned);
  the halves give a sub-octave colour.
- **FMA** the amount (brightness), **FMD** how fast it falls after the trig
  (127 holds), so FMA high with FMD around 40..70 gives an electric piano or
  bell attack that mellows.
- **FB** the modulator's feedback, towards a saw-like, then noisy, edge.

**DG ORGAN** (TUN FIN D16 DEC / D8 D5 D4 LEV)

- Four drawbars of sines: **D16** an octave below, **D8** the note, **D5** a
  fifth above it (5 1/3 ft), **D4** an octave above. Two drawbars at full reach
  full scale; with more, lower LEV or the drawbars.

**DG CHORD** (TUN FIN CHD DEC / INV DET DRV LEV)

- Four band-limited saws playing a chord on the note, so one track plays chords.
- **CHD** 0..15 picks the chord:

  | CHD | chord | notes | CHD | chord | notes |
  |---|---|---|---|---|---|
  | 0 | major | 0 4 7 12 | 8 | dim7 | 0 3 6 9 |
  | 1 | minor | 0 3 7 12 | 9 | aug | 0 4 8 12 |
  | 2 | sus2 | 0 2 7 12 | 10 | 6 | 0 4 7 9 |
  | 3 | sus4 | 0 5 7 12 | 11 | m6 | 0 3 7 9 |
  | 4 | maj7 | 0 4 7 11 | 12 | add9 | 0 4 7 14 |
  | 5 | m7 | 0 3 7 10 | 13 | m9 (no 5th) | 0 3 10 14 |
  | 6 | 7 | 0 4 7 10 | 14 | power | 0 7 12 19 |
  | 7 | m7b5 | 0 3 6 10 | 15 | octaves | 0 12 19 24 |

- **INV** 0..3, the inversion: that many of the lowest notes go up an octave.
- **DET** detunes the four notes against each other, up to about 25 cents, for a
  wider, string-machine sound. 0 is exactly in tune.
- Each saw is at a quarter, so the chord never clips.
- **DRV** drives the whole chord into soft clipping; 0 off.

**DG SUPER** (TUN FIN DET DEC / MIX SUB DRV LEV)

- A supersaw: seven band-limited saws, spaced as the JP-8000's.
- **DET** the spread, slow at first and wide at the top (the outer saws about
  1.9 semitones apart at 127). 0 is seven saws in unison.
- **MIX** raises the six side saws and lowers the centre one.
- The saws run freely from spread starting points, so every hit is slightly
  different, as on the original.
- **SUB** a sine an octave below the centre saw; **DRV** a soft-clip drive.

**DG PLUCK** (TUN FIN BRT DEC / PIK LEN DRV LEV)

- A plucked string (Karplus-Strong): a short burst of noise rings in a delay line
  tuned to the note. Tuned to within half a cent from C2 to C7 in a model of
  the code; the lowest note is about 12 Hz.
- **BRT** the brightness, of the pluck and of the string: low values are dull
  and nylon-like, 127 bright and metallic.
- **DEC** how long the string rings: from a muted thud at 0 to about a minute at
  127, the same at every pitch. 80, the default, is about a guitar's.
- **PIK** the pick position: 0 plucks at the end of the string, higher values
  nearer the middle (up to half way), hollowing the tone. 32, the default, is a
  guitar's usual spot.
- **LEN** how long the pluck lasts: 64 is one period of the note, lower a sharp
  click, higher a softer, strummed or bowed start (up to about two periods).
- **DRV** a soft-clip drive on the string, from warm to distorted guitar.
- **LEV** the level. DEC here belongs to the string, so the decay is not added on
  top as on the other DG machines.

**DG CHIP** (TUN FIN WAV DEC / ARP SPD SWP LEV)

- The NES's sound chip.
- **WAV** 0..6: 0..3 a pulse at 12.5 %, 25 %, 50 % and 75 % width; 4 the NES's
  stepped 32-step triangle (its buzz included); 5 noise, 6 the short, metallic
  noise, both pitched by the note.
- **DEC** falls in the NES's 16 volume steps; 127 holds.
- **ARP** 0 off, 1..16 an arpeggio over DG CHORD's chords (CHD + 1: 1 major,
  2 minor .. 16 octaves), cycling its four notes; **SPD** its speed, from a
  note every 67 ms at 0 to every 4 ms at 127 (about 30 ms, the NES's
  two-frame arps, near 64). It restarts on every trig.
- **SWP** slides the pitch from the trig: below 64 down, above up, faster
  further from 64, up to 5 octaves. 64 is off.

**Known limits**

- The knobs have no MIDI CC or NRPN yet. P-locks and the LFO work.
- A kit saved with these machines loads with that sound set to DISABLE on stock
  firmware.
- The level against the stock machines is not yet matched.
- DG SINE and DG SAW were played on hardware on 2026-11-12: TUN, FIN, DEC and LEV
  worked. Their other knobs, and DG PULSE, DG FM2 and DG ORGAN, are built but not
  yet run. That run found the knobs reusing SD TEST's list parameters (DET, SUB)
  stuck in the old 0..7 lists and showing ERR; the machines now replace those
  parameters' settings when first used after start-up.
- DG CHORD, DG SUPER and DG PLUCK are built but not yet run. DG SUPER is the
  heaviest machine (seven oscillators); check the sound stays clean with it on
  several tracks at once.
- CHD and INV show plain numbers, not chord names.
- Every DG machine now has all eight knobs in use. The last eight records came
  from the hidden RS FM 2 machine, which can no longer be unhidden; DG CHIP's
  from BD FM 2, likewise.
- ARP's speed is in time, not synced to the tempo.

## 0022 - FX RAM

No controls. The delay's memory is halved, from 4 MB to 2 MB, so the effects and
machines that need RAM (a chorus, wavetables, plucked strings) have 2 MB to use.

- The delay sounds as before at any time up to 5.33 s. Settings that asked for
  more (a long TIME at a slow tempo, up to 8 s on stock) hold at 5.33 s.
- Not yet run on hardware: check long delays and ping-pong at slow tempos.

## Returning to stock

Flash Elektron's stock OS 1.73 `.syx` the same way (`docs/FLASHING.md`). The mods
store their settings in bits stock firmware ignores, so projects open on stock
with the mod settings dropped.
