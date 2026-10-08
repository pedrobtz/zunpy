# The NumPy side of the conformance check (design section 15): every row
# of MANIFEST.tsv in the directory given must describe what np.load()
# reads from its file -- dtype, shape, memory order and every value -- so
# that the R suite, which compares npy_decode() with the MANIFEST, compares
# it with NumPy. Run by tools/check-fixtures.
import csv
import math
import os
import sys

import numpy as np


d = sys.argv[1]


def show(v):
    """A value as tools/make-fixtures.py writes it in a MANIFEST."""
    if isinstance(v, str):
        return "s:" + v.encode("utf-8", "surrogatepass").hex()
    if isinstance(v, (bytes, np.void)):
        return "b:" + bytes(v).hex()
    if isinstance(v, (bool, np.bool_)):
        return "True" if v else "False"
    if isinstance(v, complex):
        return f"{show(v.real)}:{show(v.imag)}"
    if isinstance(v, float):
        if v != v:
            return "nan"
        if v in (float("inf"), float("-inf")):
            return "inf" if v > 0 else "-inf"
        return v.hex()
    return str(v)


def column_tokens(flat):
    if flat.dtype.kind in "Mm":
        return ["NaT" if c == -(2**63) else str(c)
                for c in flat.view(flat.dtype.str[0] + "i8").tolist()]
    return [show(v) for v in flat.tolist()]


def record_tokens(flat):
    """As tools/make-fixtures.py writes a structured array."""
    out = []
    for name in flat.dtype.names:
        ft = flat.dtype.fields[name][0]
        base, sub = (ft.subdtype if ft.subdtype else (ft, ()))
        m = int(np.prod(sub)) if sub else 1
        col = flat[name].reshape(len(flat), m)
        for e in range(m):
            label = name if not sub else f"{name}.{e + 1}"
            if out:
                out.append("|")
            out.append("@" + label.encode().hex() + "@" + base.str)
            out.extend(column_tokens(np.ascontiguousarray(col[:, e])))
    return out


def parse(tok):
    """A MANIFEST value as a Python object: R writes floats with %a and
    Python with float.hex(), so values are compared, not strings."""
    if tok in ("True", "False"):
        return tok == "True"
    if ":" in tok:
        re, im = tok.split(":")
        return complex(parse(re), parse(im))
    if tok in ("nan", "inf", "-inf"):
        return float(tok)
    if "0x" in tok:
        return float.fromhex(tok)
    return int(tok)


def same(a, b):
    if isinstance(a, complex) or isinstance(b, complex):
        return same(complex(a).real, complex(b).real) and same(complex(a).imag, complex(b).imag)
    if isinstance(a, float) or isinstance(b, float):
        a, b = float(a), float(b)
        if a != a or b != b:
            return a != a and b != b
        return a == b and math.copysign(1, a) == math.copysign(1, b)
    return a == b


bad = 0
with open(os.path.join(d, "MANIFEST.tsv"), newline="") as fp:
    rows = list(csv.DictReader(fp, delimiter="\t", quoting=csv.QUOTE_NONE))
for r in rows:
    a = np.load(os.path.join(d, r["file"]))
    shape = ",".join(str(s) for s in a.shape)
    order = "F" if a.flags.f_contiguous and not a.flags.c_contiguous else "C"
    flat = np.array(a, order="C").reshape(-1)
    got = record_tokens(flat) if a.dtype.names is not None else column_tokens(flat)
    want = r["values"].split(" ") if r["values"] else []
    # A structured array's dtype.str is |V<itemsize>; R's MANIFEST says |V.
    descr = a.dtype.str if not (a.dtype.names and r["descr"] == "|V") else "|V"
    for what, g, w in [("descr", descr, r["descr"]), ("shape", shape, r["shape"]),
                       ("order", order, r["order"])]:
        if g != w:
            print(f"FAIL: {r['file']}: {what} is {g!r}, MANIFEST says {w!r}")
            bad += 1
    # Equal as text, or as numbers: R writes floats with %a.
    def agree(g, w):
        if g == w:
            return True
        try:
            return same(parse(g), parse(w))
        except ValueError:
            return False
    if len(got) != len(want) or not all(agree(g, w) for g, w in zip(got, want)):
        print(f"FAIL: {r['file']}: values differ: {got[:6]} against {want[:6]}")
        bad += 1
if bad:
    sys.exit(1)
print(f"==> np.load() agrees with all {len(rows)} MANIFEST rows in {d}")
