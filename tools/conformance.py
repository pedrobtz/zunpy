# The NumPy side of the conformance check (design section 15): every row
# of MANIFEST.tsv in the directory given must describe what np.load()
# reads from its file -- dtype, shape, memory order and every value -- so
# that the R suite, which compares npy_decode() with the MANIFEST, compares
# it with NumPy. Run by tools/check-fixtures.
import csv
import os
import sys

import numpy as np


d = sys.argv[1]


def show(v):
    if isinstance(v, (bool, np.bool_)):
        return "True" if v else "False"
    if isinstance(v, (complex, np.complexfloating)):
        return f"{show(float(v.real))}:{show(float(v.imag))}"
    if isinstance(v, (float, np.floating)):
        f = float(v)
        if f != f:
            return "nan"
        if f in (float("inf"), float("-inf")):
            return "inf" if f > 0 else "-inf"
        return f.hex()
    return str(int(v))


bad = 0
with open(os.path.join(d, "MANIFEST.tsv"), newline="") as fp:
    rows = list(csv.DictReader(fp, delimiter="\t", quoting=csv.QUOTE_NONE))
for r in rows:
    a = np.load(os.path.join(d, r["file"]))
    shape = ",".join(str(s) for s in a.shape)
    order = "F" if a.flags.f_contiguous and not a.flags.c_contiguous else "C"
    vals = " ".join(show(v) for v in np.array(a, order="C").reshape(-1).tolist())
    for what, got, want in [("descr", a.dtype.str, r["descr"]), ("shape", shape, r["shape"]),
                            ("order", order, r["order"]), ("values", vals, r["values"])]:
        if got != want:
            print(f"FAIL: {r['file']}: {what} is {got[:60]!r}, MANIFEST says {want[:60]!r}")
            bad += 1
if bad:
    sys.exit(1)
print(f"==> np.load() agrees with all {len(rows)} MANIFEST rows")
