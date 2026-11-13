"""Read mod 0023's audio interrupt meter off the Rytm's USB stream.

The meter build writes four words over voice slot 7 (USB channel 10), each
(tag << 24) | (data << 8), every fourth frame in turn, one block late:
    0xa5  the whole interrupt's run / 4      0x5a  the interval / 4
    0x3c  S1: parameter smoothing + per-track interpolation, ticks
    0xc3  S2: scenes, CTRL IN, velocity/AT routes, 48 performance locks, ticks
all in DMA timer 0 ticks (about 130 MHz). Shares are of the measured interval,
so the timer's exact rate does not matter.

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
BLOCK = 32
CH = 9                     # USB channel 10
TICK_HZ = 130e6
TAGS = {"run": 0xa5, "iv": 0x5a, "s1": 0x3c, "s2": 0xc3}


def decode(x):
    """Per-block arrays from an (n, 12) int32 capture, or None."""
    w = x[:, CH].astype(np.int64) & 0xffffffff
    tag, val = w >> 24, (w >> 8) & 0xffff
    out = {}
    for k, t in TAGS.items():
        v = val[tag == t][::BLOCK // 4]   # eight copies a block; keep one
        if len(v) == 0:
            return None
        out[k] = v.astype(np.float64)
    n = min(len(v) for v in out.values())
    out = {k: v[:n] for k, v in out.items()}
    out["run"] *= 4
    out["iv"] *= 4
    out["tagged"] = np.isin(tag, list(TAGS.values())).mean()
    return out


def pct(v, iv):
    return 100.0 * v / np.maximum(iv, 1)


def report(d):
    iv = d["iv"]
    blk = np.median(iv)
    print(f"{d['tagged'] * 100:.0f}% of frames tagged, {len(iv)} blocks, "
          f"interval {blk:.0f} ticks ({blk / TICK_HZ * 1e6:.0f} us at 130 MHz)")
    for k, name in (("run", "whole interrupt"), ("s1", "S1 smoothing"),
                    ("s2", "S2 scene/ctrl/perf")):
        s = pct(d[k], iv)
        print(f"  {name:20s} median {np.median(s):6.2f}%  p99 {np.percentile(s, 99):6.2f}%"
              f"  max {s.max():6.2f}%   ({np.median(d[k]):.0f} ticks)")
    print(f"  headroom (100 - p99 of whole)  {100 - np.percentile(pct(d['run'], iv), 99):.2f}%")


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
        print("whole% med/max   S1% med   S2% med   (Ctrl+C to stop)")
        while True:
            x, over = st.read(FS)
            d = decode(np.asarray(x))
            if d is None:
                print("no tagged frames"); continue
            r, s1, s2 = (pct(d[k], d["iv"]) for k in ("run", "s1", "s2"))
            print(f"{time.strftime('%H:%M:%S')}  {np.median(r):6.2f} / {r.max():6.2f}"
                  f"   {np.median(s1):6.2f}   {np.median(s2):6.2f}"
                  f"{'   (overflow)' if over else ''}", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        st.stop(); st.close()


if __name__ == "__main__":
    main()
