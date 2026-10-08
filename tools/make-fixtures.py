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
#           re:im; S and V bytes as b:<hex>, U strings as s:<hex of UTF-8>;
#           datetime64 and timedelta64 as their integer counts, NaT as NaT;
#           a structured array as one segment per R column (see
#           record_tokens()), segments separated by a "|" token; a .npz
#           (descr npz) as key=<member fixture> pairs
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
    if isinstance(v, str):
        return "s:" + v.encode("utf-8", "surrogatepass").hex()
    if isinstance(v, (bytes, np.void)):
        return "b:" + bytes(v).hex()
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


def column_tokens(flat):
    if flat.dtype.kind in "Mm":
        # The counts, with NaT spelled out.
        return ["NaT" if c == -(2**63) else str(c)
                for c in flat.view(flat.dtype.str[0] + "i8").tolist()]
    return [fmt(v) for v in flat.tolist()]


def record_tokens(flat):
    """A structured array as one segment per R column (a field, or each
    element of a subarray field in C order): "@<hex of the column name>@<the
    element dtype>" and its values in C order of the records, segments
    separated by a "|" token."""
    out = []
    for name in flat.dtype.names:
        ft = flat.dtype.fields[name][0]
        base, sub = (ft.subdtype if ft.subdtype else (ft, ()))
        m = int(np.prod(sub)) if sub else 1
        col = flat[name].reshape(len(flat), m) if sub else flat[name].reshape(len(flat), 1)
        for e in range(m):
            label = name if not sub else f"{name}.{e + 1}"
            if out:
                out.append("|")
            out.append("@" + label.encode().hex() + "@" + base.str)
            out.extend(column_tokens(np.ascontiguousarray(col[:, e])))
    return out


def save(name, a, fortran=False):
    path = os.path.join(OUT, name + ".npy")
    # np.array(order=), not np.ascontiguousarray(), which makes a 0-d array
    # 1-d.
    arr = np.array(a, order="F" if fortran else "C")
    np.save(path, arr)
    with open(path, "rb") as fp:
        digest = hashlib.sha256(fp.read()).hexdigest()
    flat = np.array(a, order="C").reshape(-1)
    if a.dtype.names is not None:
        tokens = record_tokens(flat)
    else:
        tokens = column_tokens(flat)
    # NumPy's own rule for fortran_order.
    f_order = arr.flags.f_contiguous and not arr.flags.c_contiguous
    rows.append([
        name + ".npy",
        a.dtype.str,
        ",".join(str(d) for d in a.shape),
        "F" if f_order else "C",
        NUMPY,
        digest,
        " ".join(tokens),
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

# Strings (roadmap Stage 4): U in both byte orders and memory orders, S, V.
words = ["", "a", "h\u00e9llo", "\u65e5\u672c", "\U0001F600x", "tab\tq"]
for bo, tag in (("<", "le"), (">", "be")):
    u = np.array(words, dtype=bo + "U5").reshape(2, 3)
    save(f"U5-{tag}-c", u)
    save(f"U5-{tag}-f", u, fortran=True)
save("S4-c", np.array([b"", b"abc", "\u00e9".encode(), b"wxyz", b"q", b"1 2"],
                      dtype="S4").reshape(3, 2))
save("S4-f", np.array([b"", b"abc", "\u00e9".encode(), b"wxyz", b"q", b"1 2"],
                      dtype="S4").reshape(3, 2), fortran=True)
save("V3", np.array([b"\x01\x02\x00", b"\x00\x00\x09"], dtype="V3"))

# Dates and times (roadmap Stage 4): every unit with an R class, a few
# without, both kinds, NaT, a big-endian one. Names are lower-case and
# spell out the units, since M (month) and m (minute) would collide on a
# case-insensitive file system.
NaT = np.datetime64("NaT")
times = {
    "dt-day": np.array(["1970-01-01", "1969-12-31", "2024-10-08", "NaT"], dtype="<M8[D]"),
    "dt-s": np.array(["1970-01-01T00:00:01", "2024-10-08T12:00:00", "1960-06-01", "NaT"], dtype="<M8[s]"),
    "dt-ms": np.array(["2024-10-08T12:00:00.123", "1969-12-31T23:59:59.999", "NaT"], dtype="<M8[ms]"),
    "dt-us": np.array(["2024-10-08T12:00:00.123456", "1970-01-01T00:00:00.000001", "NaT"], dtype="<M8[us]"),
    "dt-ns": np.array(["1970-01-01T00:00:00.000000001", "1970-03-01", "NaT"], dtype="<M8[ns]"),
    "dt-ns-now": np.array(["2024-10-08T12:00:00.123456789"], dtype="<M8[ns]"),
    "dt-ns-be": np.array(["1970-01-02", "NaT"], dtype=">M8[ns]"),
    "dt-year": np.array(["2024", "1969", "NaT"], dtype="<M8[Y]"),
    "dt-month": np.array(["2024-10", "NaT"], dtype="<M8[M]"),
    "td-day": np.array([0, -3, 365, "NaT"], dtype="<m8[D]"),
    "td-hour": np.array([1, 25, "NaT"], dtype="<m8[h]"),
    "td-min": np.array([90, -1], dtype="<m8[m]"),
    "td-s": np.array([1, 86400, "NaT"], dtype="<m8[s]"),
    "td-ms": np.array([1500, -1], dtype="<m8[ms]"),
    "td-us": np.array([1, 2500000], dtype="<m8[us]"),
    "td-ns": np.array([1, 1000000001, "NaT"], dtype="<m8[ns]"),
    "td-week": np.array([2, "NaT"], dtype="<m8[W]"),
    "td-ps": np.array([7, "NaT"], dtype="<m8[ps]"),
}
for name, t in times.items():
    save(name, t)
save("dt-day-2d-c", np.array(["2000-01-01", "2000-01-02", "NaT", "2000-01-04"], dtype="<M8[D]").reshape(2, 2))

# Structured dtypes (roadmap Stage 5): plain, big-endian, subarrays,
# aligned with padding, titles, more than one dimension in both orders,
# Latin-1 and non-Latin-1 field names, and no records at all.
basic = np.dtype([("id", "<i4"), ("x", "<f8"), ("name", "<U5"), ("flag", "|b1"),
                  ("t", "<M8[s]"), ("raw", "|S3")])
rec = np.zeros(4, basic)
rec["id"] = [1, -2, 3, 2**31 - 1]
rec["x"] = [0.5, np.nan, -np.inf, 1e300]
rec["name"] = ["a", "h\u00e9llo", "", "\U0001F600"]
rec["flag"] = [True, False, True, False]
rec["t"] = np.array(["2024-10-08T12:00:00", "NaT", "1970-01-01T00:00:00", "1969-12-31T23:59:59"], dtype="M8[s]")
rec["raw"] = [b"ab", b"", b"xyz", b"q"]
save("rec-basic", rec)
be = np.zeros(3, np.dtype([("i", ">i4"), ("f", ">f8"), ("c", ">c8")]))
be["i"] = [1, -1, 7]
be["f"] = [1.5, -0.0, 2.25]
be["c"] = [1 + 2j, -1j, 0]
save("rec-be", be)
sub = np.zeros(2, np.dtype([("xyz", "<f4", (3,)), ("m", "<i2", (2, 2)), ("k", "|u1")]))
sub["xyz"] = [[1, 2, 3], [4, 5, 6]]
sub["m"] = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
sub["k"] = [9, 255]
save("rec-subarray", sub)
al = np.zeros(2, np.dtype([("a", "|i1"), ("b", "<i8"), ("c", "<f4")], align=True))
al["a"] = [1, -1]
al["b"] = [2**40, -5]
al["c"] = [0.25, 8]
save("rec-aligned", al)
ti = np.zeros(2, np.dtype([(("Title A", "a"), "<i2"), ("b", "<u2")]))
ti["a"] = [1, 2]
ti["b"] = [3, 65535]
save("rec-titles", ti)
grid = np.zeros((2, 3), np.dtype([("v", "<i4"), ("w", "<f8")]))
grid["v"] = np.arange(6).reshape(2, 3)
grid["w"] = np.arange(6).reshape(2, 3) / 4
save("rec-2d-c", grid)
save("rec-2d-f", grid, fortran=True)
lat = np.zeros(2, np.dtype([("caf\u00e9", "<i4")]))
lat["caf\u00e9"] = [1, 2]
save("rec-latin1-name", lat)
utf = np.zeros(2, np.dtype([("\u20ac", "<i4"), ("b", "<f8")]))
utf["\u20ac"] = [5, 6]
save("rec-utf8-name", utf)
save("rec-empty", np.zeros(0, basic))

# Values R holds only on request (design section 6.1 notes): NA_integer_'s
# bit pattern, 64-bit integers beyond 2^53, and u8 at 2^63.
save("edge-i4-min", np.array([1, -(2**31), 3], dtype="<i4"))
save("edge-i8-big", np.array([0, 2**53 + 1, -(2**53) - 1], dtype="<i8"))
save("edge-i8-min", np.array([0, -(2**63)], dtype="<i8"))
save("edge-u8-big", np.array([0, 2**53 + 1, 2**63 - 1], dtype="<u8"))
save("edge-u8-top", np.array([0, 2**63], dtype="<u8"))
# Strings R cannot hold as they are: a NUL inside, a surrogate, bytes that
# are Latin-1 rather than UTF-8; and a count beyond 2^53 days.
save("edge-s-nul", np.array([b"a\x00b", b"c"], dtype="S3"))
save("edge-u-surrogate", np.array(["a\ud800"], dtype="<U2"))
save("edge-s-latin1", np.array(["caf\u00e9".encode("latin-1")], dtype="S4"))
save("edge-td-day-big", np.array([2**53 + 1], dtype="<m8[D]"))

# .npz archives (roadmap Stage 6), each member a fixture above, so that a
# MANIFEST row only maps keys to fixture files: "key=file.npy ...".
def save_npz(name, members, compressed=False):
    path = os.path.join(OUT, name + ".npz")
    arrays = {k: np.load(os.path.join(OUT, f)) for k, f in members.items()}
    (np.savez_compressed if compressed else np.savez)(path, **arrays)
    finish_npz(name, members)


def finish_npz(name, members):
    path = os.path.join(OUT, name + ".npz")
    with open(path, "rb") as fp:
        digest = hashlib.sha256(fp.read()).hexdigest()
    rows.append([name + ".npz", "npz", "", "", NUMPY, digest,
                 " ".join(f"{k}={f}" for k, f in members.items())])


save_npz("npz-stored", {"x": "f8-le-c.npy", "y": "i4-le-c.npy"})
save_npz("npz-compressed", {"x": "f8-le-c.npy", "s": "U5-le-c.npy", "r": "rec-basic.npy"},
         compressed=True)
save_npz("npz-empty", {})
# Positional arrays are named arr_0, arr_1, ... by numpy.savez().
np.savez(os.path.join(OUT, "npz-positional.npz"),
         np.load(os.path.join(OUT, "b1-na-c.npy")), np.load(os.path.join(OUT, "c16-le-c.npy")))
finish_npz("npz-positional", {"arr_0": "b1-na-c.npy", "arr_1": "c16-le-c.npy"})


def zip64_archive(path, members):
    """A stored archive whose directory uses every ZIP64 record although
    nothing needs them: sizes and offsets as 0xFFFFFFFF with a ZIP64 extra,
    and a ZIP64 end record with its locator. Large files are written this
    way; this one is small enough to commit."""
    import struct
    import zlib
    out = bytearray()
    central = bytearray()
    for key, f in members.items():
        with open(os.path.join(OUT, f), "rb") as fp:
            data = fp.read()
        name = (key + ".npy").encode()
        crc = zlib.crc32(data)
        offset = len(out)
        out += struct.pack("<IHHHHHIIIHH", 0x04034b50, 45, 0, 0, 0, 0x21, crc,
                           0xFFFFFFFF, 0xFFFFFFFF, len(name), 20)
        out += name + struct.pack("<HHQQ", 1, 16, len(data), len(data)) + data
        central += struct.pack("<IHHHHHHIIIHHHHHII", 0x02014b50, 0x032D, 45, 0, 0, 0, 0x21,
                               crc, 0xFFFFFFFF, 0xFFFFFFFF, len(name), 28, 0, 0, 0,
                               0o600 << 16, 0xFFFFFFFF)
        central += name + struct.pack("<HHQQQ", 1, 24, len(data), len(data), offset)
    cd_start = len(out)
    out += central
    eocd64 = len(out)
    out += struct.pack("<IQHHIIQQQQ", 0x06064b50, 44, 45, 45, 0, 0, len(members),
                       len(members), len(central), cd_start)
    out += struct.pack("<IIQI", 0x07064b50, 0, eocd64, 1)
    out += struct.pack("<IHHHHIIH", 0x06054b50, 0, 0, 0xFFFF, 0xFFFF,
                       0xFFFFFFFF, 0xFFFFFFFF, 0)
    with open(path, "wb") as fp:
        fp.write(bytes(out))


zip64_archive(os.path.join(OUT, "npz-zip64.npz"), {"a": "i2-le-c.npy", "b": "S4-c.npy"})
finish_npz("npz-zip64", {"a": "i2-le-c.npy", "b": "S4-c.npy"})

with open(os.path.join(OUT, "MANIFEST.tsv"), "w") as fp:
    fp.write("file\tdescr\tshape\torder\tnumpy\tsha256\tvalues\n")
    for r in rows:
        fp.write("\t".join(r) + "\n")
print(f"{len(rows)} fixtures written to {OUT}")
