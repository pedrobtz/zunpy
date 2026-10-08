# Writes the NumPy fixtures under tests/testthat/fixtures/npy/ and their
# MANIFEST.tsv (design section 15). Run from the package root:
#
#     uv run --no-project --with numpy==2.3.3 python tools/make-fixtures.py
#
# NumPy is pinned: tools/check-fixtures regenerates the files with this
# version and requires them byte-identical, and every MANIFEST row records
# the version that wrote it. The R suite never runs this script; it reads
# the committed files.
#
# MANIFEST.tsv columns:
#   file    the fixture's name
#   descr   the dtype as NumPy writes it
#   shape   comma-separated, empty for a 0-d array
#   order   C or F, as the header says
#   numpy   the version that wrote it
#   sha256  of the file
#   values  every element in C (row-major) order, space-separated:
#           integers in decimal; floats as float.hex() (exact, and read
#           exactly by R's as.numeric(), which decimal text at the extremes
#           is not), or nan, inf, -inf; booleans as True/False; complex as
#           re:im
import hashlib
import os
import sys

import numpy as np

NUMPY = "2.3.3"
if np.__version__ != NUMPY:
    sys.exit(f"make-fixtures: NumPy {NUMPY} is required, found {np.__version__}")

OUT = os.environ.get("ZNP_FIXTURES_OUT", "tests/testthat/fixtures/npy")
os.makedirs(OUT, exist_ok=True)
rows = []


def fmt(v):
    if isinstance(v, (bool, np.bool_)):
        return "True" if v else "False"
    if isinstance(v, (complex, np.complexfloating)):
        return f"{fmt(float(v.real))}:{fmt(float(v.imag))}"
    if isinstance(v, (float, np.floating)):
        f = float(v)
        if f != f:
            return "nan"
        if f in (float("inf"), float("-inf")):
            return "inf" if f > 0 else "-inf"
        return f.hex()
    return str(int(v))


def save(name, a, fortran=False):
    path = os.path.join(OUT, name + ".npy")
    # np.array(order=), not np.ascontiguousarray(), which makes a 0-d array
    # 1-d.
    arr = np.array(a, order="F" if fortran else "C")
    np.save(path, arr)
    with open(path, "rb") as fp:
        digest = hashlib.sha256(fp.read()).hexdigest()
    flat = np.array(a, order="C").reshape(-1)
    # NumPy's own rule for fortran_order.
    f_order = arr.flags.f_contiguous and not arr.flags.c_contiguous
    rows.append([
        name + ".npy",
        a.dtype.str,
        ",".join(str(d) for d in a.shape),
        "F" if f_order else "C",
        NUMPY,
        digest,
        " ".join(fmt(v) for v in flat.tolist()),
    ])


def values(dt, n):
    """n deterministic values of dtype dt that R can hold exactly: the
    type's own extremes where R can hold them, then a pattern."""
    k = dt.kind
    if k == "b":
        return np.array([(i * 5) % 3 == 0 for i in range(n)], dtype=dt)
    if k in "iu":
        info = np.iinfo(dt)
        lo = max(info.min, -(2**31 - 1))
        hi = min(info.max, 2**31 - 1)
        if dt.itemsize == 8:
            lo, hi = max(info.min, -(2**53)), min(info.max, 2**53)
        special = [0, 1, hi, lo, hi - 1]
        if info.min < 0:
            special += [-1]
        pattern = [lo + (i * 7919) % (hi - lo) for i in range(n)]
        return np.array((special + pattern)[:n], dtype=dt)
    if k == "f":
        fi = np.finfo(dt)
        special = [0.0, -0.0, 1.5, -2.25, np.inf, -np.inf, np.nan,
                   float(fi.max), float(fi.smallest_subnormal), float(fi.eps)]
        pattern = [(i - 7) * 0.375 for i in range(n)]
        return np.array((special + pattern)[:n], dtype=dt)
    if k == "c":
        part = np.dtype(f"<f{dt.itemsize // 2}")
        out = np.empty(n, dtype=dt)
        out.real = values(part, n)
        out.imag = values(part, n + 3)[3:]
        return out
    raise ValueError(dt)


# Every numeric, boolean and complex dtype of design section 6.1, in both
# byte orders where it has one: a 3-d array in C and Fortran order.
kinds = ["b1", "i1", "u1", "i2", "u2", "i4", "u4", "i8", "u8",
         "f2", "f4", "f8", "c8", "c16"]
for code in kinds:
    orders = ["|"] if code in ("b1", "i1", "u1") else ["<", ">"]
    for bo in orders:
        dt = np.dtype(bo + code if bo != "|" else code)
        tag = {"<": "le", ">": "be", "|": "na"}[bo]
        a = values(dt, 24).reshape(2, 3, 4)
        save(f"{code}-{tag}-c", a)
        save(f"{code}-{tag}-f", a, fortran=True)

# Shapes, on one dtype: 0-d, vector, matrix, zero-length, many dimensions.
dt = np.dtype("<f8")
save("shape-scalar", values(dt, 1).reshape(()))
save("shape-vector", values(dt, 5))
save("shape-matrix-c", values(dt, 6).reshape(2, 3))
save("shape-matrix-f", values(dt, 6).reshape(2, 3), fortran=True)
save("shape-empty", values(dt, 0).reshape(0, 3))
save("shape-5d-c", values(np.dtype("<i4"), 32).reshape(2, 1, 2, 4, 2))
save("shape-5d-f", values(np.dtype("<i4"), 32).reshape(2, 1, 2, 4, 2), fortran=True)

# Values R holds only on request (design section 6.1 notes): NA_integer_'s
# bit pattern, 64-bit integers beyond 2^53, and u8 at 2^63.
save("edge-i4-min", np.array([1, -(2**31), 3], dtype="<i4"))
save("edge-i8-big", np.array([0, 2**53 + 1, -(2**53) - 1], dtype="<i8"))
save("edge-i8-min", np.array([0, -(2**63)], dtype="<i8"))
save("edge-u8-big", np.array([0, 2**53 + 1, 2**63 - 1], dtype="<u8"))
save("edge-u8-top", np.array([0, 2**63], dtype="<u8"))

with open(os.path.join(OUT, "MANIFEST.tsv"), "w") as fp:
    fp.write("file\tdescr\tshape\torder\tnumpy\tsha256\tvalues\n")
    for r in rows:
        fp.write("\t".join(r) + "\n")
print(f"{len(rows)} fixtures written to {OUT}")
