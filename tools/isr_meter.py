"""Read mod 0023's audio interrupt meter off the Rytm's USB stream.

The meter build writes 32 words over voice slot 7 (USB channel 10), one a frame, (tag << 24) | (value << 8), one block late:
    0x50  the whole interrupt's run / 4      0x51  the interval / 4
    0x52..0x65  twenty sections along the interrupt's main path, in ticks
    0x66  a block counter                    0x67..0x6f  0
all in DMA timer 0 ticks (about 130 MHz). Shares are of the measured interval,
so the timer's exact rate does not matter. See mods/0023-isr-meter/stub.s for
where each section starts and ends.

The Rytm's USB CONFIG must be OVERBRIDGE, the mode with 12 inputs. On Windows
those 12 come through Overbridge's ASIO driver, which this script enables in
sounddevice (SD_ENABLE_ASIO); the 2-input "Elektron Analog Rytm mkII" WDM
devices carry MAIN only.

    isr_meter.py --list           the input devices with 12 or more inputs
    isr_meter.py                  one reading, 5 s, from the first such device
                                  whose name mentions Rytm or Overbridge
    isr_meter.py --seconds 20
    isr_meter.py --device 41      or a part of its name
    isr_meter.py --live           a line a second until Ctrl+C: turn effects on
                                  and off and watch the share move
"""
import argparse
import os
import sys
import time

os.environ.setdefault("SD_ENABLE_ASIO", "1")   # before sounddevice loads PortAudio

import numpy as np  # noqa: E402
import sounddevice as sd  # noqa: E402

FS = 48000
CH = 9                     # USB channel 10
TICK_HZ = 130e6
SECTIONS = [
    "pre: entry, trigs, voice set-up",
    "parameter smoothing + interpolation",
    "scenes, CV in, vel/AT routes",
    "LFOs + LFO RND (0004)",
    "machines (+ portamento)",
    "0x4011c64c (sample layer?)",
    "0x4010ea2c",
    "filter envelopes (0x4010d090)",
    "amp envelopes (0x401098d4)",
    "mute/solo loop",
    "route_all (0013) + master volume",
    "0x40121306..0x4012132c",
    "0x4010e1a0 (frame set-up)",
    "return mixers PRE/POST",
    "receive fill + DAC SUM (0013)",
    "stock delay + reverb (+0019 pre)",
    "REVERB 2 / phaser / DIST FILTER",
    "sampler and the rest",
    "USB send (Overbridge)",
    "voice DMA copy + exit",
]


# The live view's columns: section indices (0-based), or (first, last) summed.
LIVE = (0, 4, (5, 13), 14, 15, 16, 18)


def group(d, k):
    if isinstance(k, tuple):
        return d["sec"][:, k[0]:k[1] + 1].sum(1)
    return d["sec"][:, k]


def decode(x):
    """Per-block arrays from an (n, 12) int32 capture, or None."""
    w = x[:, CH].astype(np.int64) & 0xffffffff
    tag, val = w >> 24, (w >> 8) & 0xffff
    cols = []
    for t in range(0x50, 0x52 + len(SECTIONS)):
        v = val[tag == t]                 # one copy a block
        if len(v) == 0:
            return None
        cols.append(v.astype(np.float64))
    n = min(len(c) for c in cols)
    cols = [c[:n] for c in cols]
    wait = val[tag == 0x67].astype(np.float64)[:n]
    if len(wait) < n:
        wait = np.zeros(n)
    return {"run": cols[0] * 4, "iv": cols[1] * 4, "sec": np.stack(cols[2:], 1), "wait": wait,
            "tagged": ((tag >= 0x50) & (tag <= 0x6f)).mean()}


def pct(v, iv):
    return 100.0 * v / np.maximum(iv, 1)


def report(d):
    iv = d["iv"]
    blk = np.median(iv)
    print(f"{d['tagged'] * 100:.0f}% of frames tagged, {len(iv)} blocks, "
          f"interval {blk:.0f} ticks ({blk / TICK_HZ * 1e6:.0f} us at 130 MHz)")
    r = pct(d["run"], iv)
    print(f"  {'WHOLE INTERRUPT':38s} median {np.median(r):6.2f}%  p99 {np.percentile(r, 99):6.2f}%"
          f"  max {r.max():6.2f}%")
    total = 0.0
    for k, name in enumerate(SECTIONS):
        s = pct(d["sec"][:, k], iv)
        total += np.median(s)
        print(f"  {k + 1:2d} {name:35s} median {np.median(s):6.2f}%  p99 {np.percentile(s, 99):6.2f}%"
              f"  max {s.max():6.2f}%")
    w = pct(d["wait"], iv)
    print(f"     of 6: entry + sample-DMA wait  median {np.median(w):6.2f}%  p99 {np.percentile(w, 99):6.2f}%"
          f"  max {w.max():6.2f}%")
    print(f"  sum of section medians {total:.2f}%;  headroom (100 - p99 of whole)"
          f" {100 - np.percentile(r, 99):.2f}%")


def wide_inputs():
    out = []
    for i, d in enumerate(sd.query_devices()):
        if d["max_input_channels"] >= 12:
            api = sd.query_hostapis(d["hostapi"])["name"]
            out.append((i, d["name"], d["max_input_channels"], api))
    return out


def pick_device(want):
    devs = wide_inputs()
    if want is not None:
        if want.isdigit():
            return int(want)
        for i, name, _, _ in devs:
            if want.lower() in name.lower():
                return i
        raise SystemExit(f"no input device with 12+ inputs matching {want!r}; try --list")
    for i, name, _, _ in devs:
        if "rytm" in name.lower() or "overbridge" in name.lower():
            return i
    lines = ["no input device with 12+ inputs named Rytm or Overbridge.",
             "Rytm: SETTINGS > SYSTEM > USB CONFIG > OVERBRIDGE; on Windows the",
             "Overbridge driver's ASIO device carries the 12 channels.",
             "devices with 12+ inputs:"]
    lines += [f"  [{i}] {n} - {c} in ({api})" for i, n, c, api in devs] or ["  none"]
    lines.append("pick one with --device N if it is the Rytm under another name.")
    raise SystemExit("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seconds", type=float, default=5.0)
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--device", default=None, help="index or part of the name")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list:
        for i, n, c, api in wide_inputs():
            print(f"[{i}] {n} - {c} in ({api})")
        return
    dev = pick_device(a.device)
    print(f"reading [{dev}] {sd.query_devices(dev)['name']}")
    st = sd.InputStream(samplerate=FS, channels=12, dtype="int32", device=dev, blocksize=1024)
    st.start()
    try:
        st.read(FS // 2)                  # the stream's first moments are not audio
        if not a.live:
            x, _ = st.read(int(a.seconds * FS))
            d = decode(np.asarray(x))
            if d is None:
                raise SystemExit("no tagged frames on channel 10: is the 0023 build flashed?")
            report(d)
            return
        print("whole% med/max | pre    | machine| sect 6 | DACSUM | dly+rev| REV2   | USB    (Ctrl+C)")
        while True:
            x, over = st.read(FS)
            d = decode(np.asarray(x))
            if d is None:
                print("no tagged frames"); continue
            r = pct(d["run"], d["iv"])
            m = [np.median(pct(group(d, k), d["iv"])) for k in LIVE]
            print(f"{time.strftime('%H:%M:%S')}  {np.median(r):6.2f} / {r.max():6.2f} | "
                  + " | ".join(f"{v:6.2f}" for v in m)
                  + ("   (overflow)" if over else ""), flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        st.stop(); st.close()


if __name__ == "__main__":
    main()
