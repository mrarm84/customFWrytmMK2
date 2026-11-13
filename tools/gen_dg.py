"""Registry claims for a DG machine (mod 0021) in a hidden machine slot.

    gen_dg.py fold          prints the claims for one machine in MACHINES

Each machine takes a hidden slot's dispatch entry, availability, names, SYNTH
knob row and its eight parameter records, as 0021's batches 1..3 did by hand.
The `expect` bytes come from build/stock_mainos.bin, so run `make build` first.
Records: sound indices 9..16 go to the slot's ids in ascending order (9 LEV,
10 TUN, 11 DEC, 12 FIN, 13..16 the machine's own), each a 40-byte body
{machine, index, 0, max, default, display, -1, -1, 0, modflags 0x600} plus its
long and short name pointers at +0x28 and +0x30.
"""
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = 0x40000400
DISPATCH = 0x4029037c          # machine_engine_table, 4 bytes a machine
AVAIL = 0x401bf17c             # 2 bytes a machine
NAMES = 0x401bef84             # {long, short} pointers, 8 bytes a machine
KNOBS = 0x40287cc8             # synth_page_knob_table: {page name, 8 ids}, 36 bytes
REC = 0x401bf918               # ROM parameter records, 0x34 bytes
REC_STRIDE = 0x34

# knob: (label, long-name symbol, short-name symbol, max, default, display)
STD = {
    "LEV": ("txt_lev_l", "txt_lev_s", 0x7f00, 0x6400, 0),
    "TUN": ("txt_tun_l", "txt_tun_s", 0x7f00, 0x4000, 0),
    "DEC": ("txt_dec_l", "txt_dec_s", 0x7f00, 0x7f00, 0),
    "FIN": ("txt_fin_l", "txt_fin_s", 0x7f00, 0x4000, 1),
    "SUB": ("txt_sub_l", "txt_sub_s", 0x7f00, 0x0000, 0),
}

MACHINES = {
    "fold": {
        "slot": 36, "entry": "dg_fold", "names": ("txt_fold_long", "txt_fold_short"),
        "ids": list(range(342, 350)),
        # sound indices 13..16
        "own": [("FLD", "txt_fld_l", "txt_fld_s", 0x7f00, 0x0000, 0),
                ("SYM", "txt_sym_l", "txt_sym_s", 0x7f00, 0x4000, 1),
                ("FEN", "txt_fen_l", "txt_fen_s", 0x7f00, 0x0000, 0),
                ("SUB",) + STD["SUB"]],
        "row": ["TUN", "FIN", "FLD", "DEC", "SYM", "FEN", "SUB", "LEV"],
        "title": "DG FOLD",
    },
}


def main():
    name = sys.argv[1]
    m = MACHINES[name]
    img = (ROOT / "build" / "stock_mainos.bin").read_bytes()

    def at(addr, n):
        return img[addr - BASE:addr - BASE + n].hex()

    slot, ids = m["slot"], m["ids"]
    knobs = [("LEV",) + STD["LEV"], ("TUN",) + STD["TUN"], ("DEC",) + STD["DEC"],
             ("FIN",) + STD["FIN"]] + m["own"]
    by_label = {k[0]: (ids[i], 9 + i, k) for i, k in enumerate(knobs)}
    out = []

    def patch(comment, addr, size, replace=None, sym=None):
        out.append(f"# {comment}\n[[patch]]\nowner   = \"0021-dg-machines\"\n"
                   f"addr    = 0x{addr:08x}\nsize    = {size}\nexpect  = \"{at(addr, size)}\"")
        out.append(f"from_symbol = \"{sym}\"\n" if sym else f"replace = \"{replace}\"\n")

    patch(f"Machine {slot}'s dispatch entry becomes {m['entry']}.",
          DISPATCH + 4 * slot, 4, sym=m["entry"])
    patch(f"Availability of machine {slot}: no home track, every voice.",
          AVAIL + 2 * slot, 2, replace="ffff")
    patch(f"Machine {slot}'s long name.", NAMES + 8 * slot, 4, sym=m["names"][0])
    patch(f"Machine {slot}'s short name.", NAMES + 8 * slot + 4, 4, sym=m["names"][1])
    row = "".join(f"{by_label[k][0]:08x}" for k in m["row"])
    patch(f"SYNTH page knobs of machine {slot}, {m['title']}: {' '.join(m['row'])}.",
          KNOBS + 36 * slot + 4, 32, replace=row)
    for label, (rid, idx, k) in by_label.items():
        _, lsym, ssym, mx, dflt, disp = k
        body = struct.pack(">10I", slot, idx, 0, mx, dflt, disp,
                           0xffffffff, 0xffffffff, 0, 0x600).hex()
        r = REC + rid * REC_STRIDE
        patch(f"Record {rid}: machine {slot}, sound index {idx}, {label}: 0..0x{mx:x}, "
              f"default 0x{dflt:x}{', centred' if disp else ''}.", r, 40, replace=body)
        patch(f"Record {rid}'s long name.", r + 0x28, 4, sym=lsym)
        patch(f"Record {rid}'s short name.", r + 0x30, 4, sym=ssym)
    print("\n".join(out))


if __name__ == "__main__":
    main()
