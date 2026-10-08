# zunpy — Design

- **Status:** Draft, 2026-10-08. Adopted from
  [RFC 0003](https://github.com/pedrobtz/packages/blob/main/rfcs/0003-zunpy-numpy-arrays.md)
  (2026-10-07, `pedrobtz/packages@077bb16`) as the package's own
  specification. No code exists yet; the roadmap's **Status:** lines say
  what does. Every statement here is a decision; things not yet decided
  live in §18 and nowhere else. Amend this file in the same commit as the
  code that changes it. [roadmap.md](roadmap.md) sequences the work; its
  section references (§) point here.
- **Package:** `zunpy`; consumes `zubin` and `zufast` through `LinkingTo`,
  and `zukomp` for deflated `.npz` members.
- **Source:** the family review of 2026-10-05, zubin's `ideas.md` and
  `design.md`, zufast's design §8, §16 and §17, zucbor's design (the
  check-then-build shape and the limits), and NumPy's format specification
  (`numpy/lib/format.py`, NEP 1) as of NumPy 2.x. Nothing below was checked
  against a running NumPy; section 15 says how that will be done.

**What changed between the RFC and this document.** On 2026-10-08 the
sibling checkouts (`../zubin`, `../zufast`, `../zukomp`, `../zucbor`,
`../zuxml`) were read against the RFC's assumptions. What held: zubin's
`rw.h` kernels, `zb_host_big_endian()`, the `zb_buf` builder, `bin_take()`,
the `int64 =` and `na =` arguments of `bin_decode()` and `bin_unpack()`,
`x<n>` padding and `[count]` subarrays in the layout grammar; zufast's
`bits.h`, `number.h` (`zuf_parse_i64`) and `utf8.h` (`zuf_utf8_valid`);
`cbor_read()` and `zu_open_input()` to copy. What did not hold is corrected
in place and marked *verified 2026-10-08*:

- zukomp 0.1.0 already registers a raw-DEFLATE codec, named
  `"deflate-raw"` (`"deflate"` is the zlib-wrapped one). D5 needs no
  request (§3, §10, §17).
- None of `zubin`, `zufast` and `zukomp` is on CRAN, and zubin is at
  `0.0.0.9000`; all three are `Remotes:` in development and all three
  precede zunpy on CRAN (§14).
- Half floats are zubin's (`zb_rd_f16le`, `zb_wr_f16le`, the `f16` layout
  type), not zufast's (§3, §6.1).
- zubin has no complex type and no layout type for `U<n>`, `M8` or `m8`;
  those are zunpy's own conversions (§3, §6.1, §6.3).
- zukomp ships a miniz ZIP *reader* in `libzukomp.a`; §10 says why zunpy
  still reads the container itself.
- Lazy reads need zubin 0.3.0 (views) and 0.4.0 (memory maps), and land in
  zunpy 0.2.0 (§2, §13).

The RFC's roadmap (its §19) became [roadmap.md](roadmap.md); §19 here now
only points there.

## 1. What zunpy is

`zunpy` reads and writes NumPy's array files, `.npy` (one array) and `.npz`
(a ZIP of `.npy` members), to and from ordinary R vectors, matrices, arrays
and data frames. It needs no Python: the format is a short ASCII header
followed by raw bytes, and every byte-level operation it needs already
exists in `zubin` (typed codecs at every width and byte order, half
floats, record layouts) and `zufast` (UTF-8, number parsing). The package
is the composition of those two with one new parser, for the header, and a
few conversions zubin has no type for: complex, UCS-4 strings and
`datetime64` (*verified 2026-10-08*).

It is a *format* package in the family's terms, like `zucbor` and
`zuhtml`: an R API over a fixed binary format, with no C API of its own.

The one-line statement that governs every decision below:

> **Move arrays between R and NumPy exactly, with the header validated
> before anything is allocated, and with no Python installed.**

Three properties shape the design, inherited from `zucbor`:

- **Validate before building.** The header is parsed and checked whole,
  the declared shape is multiplied and compared with the bytes on hand,
  and only then is an R object allocated. A header is untrusted input: it
  is a Python literal that NumPy itself evaluates with `ast.literal_eval`
  under a size cap because of a past denial-of-service.
- **Writing is deterministic.** Identical R objects produce identical
  bytes: a fixed header layout, a fixed padding, little-endian always.
- **Exact or refused.** A value that does not fit its target, in either
  direction, is an error with its index, never a rounding or a wrap. This
  is `zubin`'s rule (its §14.4) and zunpy inherits it by using `zubin`'s
  codecs.

## 2. Scope

**In v0.1.0:**

- `.npy` read and write, format versions 1.0, 2.0 and 3.0.
- `.npz` read and write, stored members; deflated members through `zukomp`
  (§10).
- Numeric, boolean and complex dtypes; half precision through `zubin`.
- Fixed strings `S<n>` and `U<n>`.
- `datetime64` and `timedelta64`, to `POSIXct`, `Date` and `difftime`.
- Structured dtypes (record arrays), as data frames through `zubin`
  layouts, including subarray fields.
- Reading from a path, URL or connection, bounded, as `cbor_read()` does.
- Writing a data frame as a record array.

**Later, when asked:**

- Nested structured fields (a field whose dtype is itself structured).
- Memory-mapped, lazy reads, on `zubin` views (zubin 0.3.0) and memory
  maps (zubin 0.4.0), in zunpy 0.2.0 (*verified 2026-10-08*).

**Never:**

- Object dtype (`O`) and pickled payloads: that is Python, not a format.
- `float128` / `longdouble` (`g`): R has no type for it.
- Nested `.npz` inside `.npz`; appending to a `.npz` in place (rewrite
  the archive instead).
- A pickle reader of any kind.

The package decodes and encodes one container format. It does not
evaluate Python, does not implement NumPy semantics (broadcasting, dtype
promotion) and does not know what the arrays mean.

## 3. Position in the `zu*` family

The rows for `zu-family.md` (alignment R1), with the recommended forms:

| | zunpy |
| --- | --- |
| Role | format |
| R prefix | `npy_` |
| Info function | `zunpy_info()` |
| Root condition class | `zunpy_error` |
| Public C prefix | none; internal `znp_` / `ZNP_` |
| From C | no C API; `LinkingTo` consumer only |
| Hides symbols | yes, from Stage 0 (R3) |
| Vendored code | none |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

The info function takes the package name, which R1 recommends for new
packages. The `znp_` prefix was checked on 2026-10-07 against `zu_`,
`zuf_`, `zb_`, `zuc_`, `zux_`, `zuh_`, `zurand_`, `zusat_` and `zusmt_`;
Stage 0 verifies it again.

**Relationships, as decided rather than as hoped:**

- **`zubin`** owns every typed read and write: `zb_rd_*` and `zb_wr_*`
  from `rw.h` for the kernels, including `f2` (`zb_rd_f16le`,
  `zb_wr_f16le` and the `be` forms), `bin_decode()` and `bin_encode()` for
  the whole-array path, and `bin_layout()`, `bin_unpack()` and `bin_pack()`
  for structured dtypes. zunpy adds no byte-swapping or narrowing code of
  its own. *Verified 2026-10-08:* zubin has no complex type and no layout
  type for UCS-4 strings or `datetime64`. zunpy reads `c8` and `c16` as
  pairs of `f32` or `f64` through the kernels, and in a structured dtype
  declares a `U<n>` field as `b<4n>` and an `M8` or `m8` field as `i64`,
  converting the unpacked column itself (§6.3).
- **`zufast`** owns UTF-8 validation for `U` strings after conversion
  (`zuf_utf8_valid`) and the integer parser for the shape tuple
  (`zuf_parse_i64`). zunpy includes `<zufast/bits.h>`, `<zufast/number.h>`
  and `<zufast/utf8.h>` only. Half floats are zubin's, not zufast's
  (*verified 2026-10-08*).
- **`zukomp`** owns DEFLATE. `.npz` members written by
  `numpy.savez_compressed` are raw DEFLATE streams inside ZIP local-file
  records; zukomp 0.1.0 registers the codec `"deflate-raw"` for exactly
  this (*verified 2026-10-08*; D5).
- **`zucbor`** is the template for the check-then-build structure, the
  limits, the condition classes, and `read` versus `decode` naming.
  Nothing is shared in code.
- **`bit64`**: `i8` and `u8` beyond 2^53 follow `zubin`'s `int64 =`
  argument and return `integer64` on request, with `bit64` in `Suggests`,
  never `Imports`.
- **`reticulate`** is not used: NumPy is the oracle through Python scripts in CI (§15).

**Consumers.** None named. The users are people exchanging arrays between
R and Python pipelines, CI jobs that must not install Python, and anyone
reading a `.npz` dataset in R. zunpy is useful on its own, which is the
family's admission test for a package.

**What exists elsewhere.** `RcppCNPy` (CRAN) reads and writes `.npy` and
gzipped `.npy` through the C++ `cnpy` library: integer and double matrices
only, no `.npz` write, no half floats, strings, complex or structured
dtypes, and no shape or size checks before allocation. `reticulate` reads
anything NumPy can, at the cost of a Python installation. `arrow` and
`nanoparquet` cover columnar files but not `.npy`. The gap zunpy fills is
the full dtype table with no Python and with the hostile-input discipline
of this family.

## 4. Architecture

Two phases, as in `zucbor`, and for the same reason: a length in a header
must never drive an allocation.

```text
raw / file / connection
      |
      v
  check phase  (src/znp_header.c, R-free)
      - magic, version, header length, 64-byte alignment
      - the dict grammar: exactly the keys descr, fortran_order, shape
      - descr: byte order, kind, width; or a structured list
      - shape: 0..32 dimensions, each a non-negative integer
      - product(shape) * itemsize == bytes after the header, saturating
      - limits: max_header, max_size, max_dims, max_fields
      |
      v   a plan: dtype, itemsize, shape, order, data offset
  build phase  (src/znp_build.c, R)
      - allocate the R vector from the plan, never from the header
      - convert through zubin's rw.h kernels, in column-major order
      - attach dim; permute C-order arrays in C (one pass)
      - strings: NUL-strip, encode, validate UTF-8
      |
      v
  R value
```

The check phase is R-free behind `znp_check.h`, so it builds with
`-DZNP_STANDALONE` and a libFuzzer target as `zucbor`'s walk does. It uses
`zufast`'s integer parser for the shape, nothing else from outside C99.

The writer is one pass into a raw vector (*settled at Stage 3*, in place
of a `zubin` builder): the header is formatted into a fixed-size stack
buffer, and since its length and the data's are known before anything is
written, the result is allocated once at its final size and filled
through zubin's pack kernels (`zb_pack_i32`, `zb_pack_f64`, `zb_pack_i64`
in `zubin/layout.h`). R owns every byte from the start, so an interrupt
or a refused value mid-write leaks nothing and nothing is copied. A
builder earns its place for `.npz` (Stage 6), whose size is not known up
front.

## 5. Public R API (complete v0.1.0 surface)

```r
# read
npy_read(file, ...)        # path, URL or connection -> array,
                           # or a named list for .npz
npy_decode(x, ...)         # raw vector -> array
npy_header(file)           # the parsed header, no data read
npy_names(file)            # member names of a .npz, no data read

# write
npy_write(x, file, ...)    # array -> .npy; named list -> .npz
npy_encode(x, ...)         # array -> raw vector

# type mapping, for callers who need to be explicit
npy_dtype(x)               # the descr string npy_write() would use

zunpy_info()               # zubin and zufast versions compiled against,
                           # host byte order, build flags
```

Seven functions plus the info function. The `read`/`decode` split is
`zucbor`'s: `npy_decode()` takes bytes already in memory; `npy_read()` is
the bounded reader of §12 over a path, URL or connection, following
`zuxml`'s `zu_open_input()` conventions.

### Read arguments

```r
npy_read(
  file,
  names      = NULL,                  # .npz: a character vector of members
  order      = c("R", "file"),        # section 6.4
  int64      = c("double", "integer64"),
  na         = c("error", "allow"),
  strings    = c("character", "raw"), # S<n> as text or a list of raw
  encoding   = "UTF-8",               # the encoding of S<n> bytes
  datetime   = c("convert", "integer64"),
  max_size   = 2 * 1024^3,            # bytes, the whole input
  max_header = 10000L,                # bytes, NumPy's own default
  max_dims   = 32L                    # NumPy's own limit
)
```

`npy_decode()` takes the same arguments except `file` and `names`.
`npy_header()` and `npy_names()` take `file` and `max_header` only.

### Write arguments

```r
npy_write(
  x, file,
  dtype    = NULL,                    # NULL: section 7; or a descr string
  order    = c("F", "C"),             # fortran_order in the header, section 8
  compress = FALSE,                   # .npz only
  na       = c("error", "allow"),
  encoding = "UTF-8",                 # for S<n> output
  unit     = c("us", "ns", "ms", "s") # POSIXct -> datetime64
)
```

`npy_encode()` takes the same arguments except `file` and `compress`.

**Why `npy_read()` handles `.npz` too, rather than an `npz_` prefix.** One
R prefix per package is the family rule. The file kinds are told apart by
their first bytes (`\x93NUMPY` against `PK\x03\x04`), so detection costs
nothing and cannot be wrong. A `.npz` reads as a named list, and a named
list writes as a `.npz`; `npy_write()` refuses an unnamed list, since
`.npy` has no list type and an `.npz` member needs a name. The alternative,
`npz_read()` and `npz_write()`, is recorded in D2 and can be added as
aliases if users ask.

## 6. `.npy` to R

### 6.1 Scalars and plain arrays

The `descr` string is `[byteorder]kind[width]`. Byte order is `<`
(little), `>` (big), `|` (not applicable, one-byte types) or `=` (native,
which NumPy never writes but `npy_read()` accepts as little-endian with a
warning, since the writer's byte order is unknowable).

| `descr` | R |
| --- | --- |
| `b1` | `logical` |
| `i1`, `i2`, `u1`, `u2` | `integer` |
| `i4` | `integer` |
| `u4`, `i8`, `u8` | `double`, or `integer64` |
| `f2` | `double` |
| `f4`, `f8` | `double` |
| `c8`, `c16` | `complex` |
| `S<n>` | `character`, or a `list` of `raw` |
| `U<n>` | `character` |
| `M8[D]` | `Date` |
| `M8[s]`, `M8[ms]`, `M8[us]`, `M8[ns]` | `POSIXct`, UTC |
| `M8[<other>]` | `integer64` with an `npy_dtype` attribute |
| `m8[<unit>]` | `difftime` |
| `V<n>` | `list` of `raw` |
| `O` | `zunpy_unsupported_type` |
| `g`, `f16`, `c32` | `zunpy_unsupported_type` |

Notes, by row:

- `b1`: any non-zero byte is `TRUE` (NumPy writes 0 or 1). The file has
  no missing boolean.
- `i4`: `-2^31` is `NA_integer_` in R, so reading it is an error unless
  `na = "allow"` (zubin §14.3).
- `u4`, `i8`, `u8`: a value above 2^53 in magnitude is an error with
  `int64 = "double"`; `int64 = "integer64"` returns `bit64`'s class, and
  `u8` at or above 2^63 is an error either way.
- `f2`: through zubin's `zb_rd_f16le` and `zb_rd_f16be`, exactly.
- `f4`, `f8`: exactly, every NaN payload kept, so an `NA_real_` written by
  `npy_write()` reads back as `NA`.
- `S<n>`: NUL-padded bytes; trailing NULs are stripped; decoded from
  `encoding` and validated as UTF-8. `strings = "raw"` returns the bytes,
  trailing NULs stripped as NumPy strips them. *Settled at Stage 4:*
  `encoding` is `"UTF-8"` (validated; invalid bytes are
  `zunpy_invalid_error`), `"latin1"` (converted to UTF-8) or `"bytes"`
  (marked as bytes), the three zubin's `bin_unpack()` knows; a NUL inside
  a value cannot live in an R string and is `zunpy_unrepresentable`
  unless `strings = "raw"`.
- `U<n>`: UCS-4 code points in the file's byte order, NUL-padded,
  converted to UTF-8. A surrogate or a code point above U+10FFFF is
  `zunpy_invalid_error`.
- `M8[ns]`: a double loses precision beyond 2^53 ns, about 104 days from
  the epoch; `datetime = "integer64"` keeps the raw count.
- `M8[<other>]`: the units `Y`, `M`, `W`, `h`, `m`, `ps`, `fs` and `as`
  fit no R class. The `integer64` carries the dtype in an `npy_dtype`
  attribute (*settled at Stage 4*, in place of a `unit` attribute), and
  `npy_write()` writes such a vector back as that dtype.
- `m8[<unit>]`: `D` gives days and `s` seconds; `ms`, `us` and `ns` are
  scaled to seconds; `m`, `h` and `W` give minutes, hours and weeks,
  which `difftime` has (*settled at Stage 4*); other units are returned as
  for `M8`.
- *Counts to doubles (settled at Stage 4).* A count up to 2^53 is exact
  as a double, so one division by the ticks per unit rounds correctly;
  beyond, the whole units are split off first and only the fraction is
  rounded, which gives the nearest double where a plain division would
  not (`2024-10-08T12:00:00.123456789` in `ns` is the double nearest the
  instant). A count in a whole unit (`D`, `s`, `m`, `h`, `W`) beyond 2^53
  would not be exact and is `zunpy_unrepresentable`.
- NaT (not-a-time) is `INT64_MIN` and becomes `NA` of the target class.
- `O` is a pickled object; `g`, `f16` and `c32` are long double.

**Byte order is a header property, never a guess.** Big-endian data is
read with `zb_rd_*be` kernels element by element; there is no `memcpy`
fast path that depends on the host, so a big-endian host reads a
little-endian file identically. The little-endian fast path, a single
`memcpy` when host order matches and the type is `i4`, `f8` or `c16`, is
a Stage 7 optimisation gated by `zb_host_big_endian()`.

### 6.2 Shape and dimensions

| `shape` | R |
| --- | --- |
| `()` | a length-1 vector with no `dim` |
| `(n,)` | a vector of length n, no `dim` |
| `(n, m)` | a matrix |
| `(d1, ..., dk)`, k at most 32 | an array with `dim = c(d1, ..., dk)` |

A dimension of 0 anywhere gives an empty vector with the `dim` kept. An
R array's `dim` is `integer`, so any dimension above `2^31 - 1` is
`zunpy_unrepresentable` even when the product would fit a long vector
(`zucbor`'s `ZU_ERR_DIMENSION` rule). The product may exceed `2^31 - 1`:
R holds a long vector, with or without `dim`, so only a product above
R's `R_XLEN_T_MAX` is refused (*settled at Stage 2*: the RFC said R could
not hold a long array, which is not so).

### 6.3 Structured dtypes

`descr` may be a list of `(name, descr)` or `(name, descr, shape)` tuples,
with optional titles. zunpy translates it to a `zubin` layout spec:

```text
[('id', '<u4'), ('ts', '<i8'), ('price', '<f8'), ('side', '|u1')]
   -> "<id:u32 ts:i64 price:f64 side:u8"
```

and the data block is one `bin_unpack()` call, giving a data frame with one
row per element. Alignment follows the header: NumPy writes offsets
explicitly only for `align=True` dtypes, as a dict form with `names`,
`formats`, `offsets` and `itemsize`; both forms are parsed, and explicit
offsets become `x<n>` padding fields in the spec. Field types are the
plain table above. zubin's layout grammar has no type for three of them
(*verified 2026-10-08*): a `U<n>` field is declared `b<4n>` and its bytes
decoded from UCS-4 by zunpy; an `M8` or `m8` field is declared `i64` and
given its class by zunpy; a `c8` or `c16` field is declared as two
`f32` or `f64` fields, `<name>.re` and `<name>.im`, and combined into one
complex column. Writing reverses each. A subarray field `('xyz', '<f4', (3,))` becomes
`xyz:f32[3]`, which `bin_unpack()` expands to `xyz.1 … xyz.3` columns
(zubin §13.3). A nested structured field is `zunpy_unsupported_type` in
0.1.0 (§2).

A structured array with `shape = (n,)` is a data frame of n rows. A
structured array with k > 1 dimensions is a data frame of `prod(shape)`
rows in column-major order carrying a `dim` attribute named `npy_shape`,
since R has no array of records; this is documented as lossy for
`npy_write()` unless the attribute is present (§7.4).

### 6.4 Memory order

NumPy's default is C order (last index fastest). R's is Fortran order
(first index fastest), which NumPy writes when `fortran_order` is `True`.

- `order = "R"` (default): the result is a normal R array, indexed as
  NumPy indexes it: `a[i, j]` in R is `a[i-1, j-1]` in Python. A
  Fortran-order file is copied straight. A C-order file is read into an
  array with reversed `dim` and permuted in C in one pass (the transpose
  `zucbor` does for tag 40), so the cost is one extra copy of the data,
  never a recursion.
- `order = "file"`: no permutation. A C-order file gives an R array with
  `dim = rev(shape)`, whose memory is byte-identical to the file. For a
  reader that wants the bytes and will index by hand, or will write the
  array back, it is free.

Vectors and 0-d arrays have no order question.

## 7. R to `.npy`

### 7.1 Scalars and vectors

| R | `descr` |
| --- | --- |
| `logical` | `\|b1` |
| `integer` | `<i4` |
| `double` | `<f8` |
| `complex` | `<c16` |
| `raw` | `\|u1` |
| `character` | `<U<n>`, or `\|S<n>` with `dtype = "\|S"` |
| `factor` | its labels, as `character` |
| `integer64` (bit64) | `<i8` |
| `Date` | `<M8[D]` |
| `POSIXct` | `<M8[us]`; `unit =` chooses |
| `difftime` | `<m8[unit]`, from `units()` |
| matrix, array | the vector's `descr` with `shape = dim(x)` |
| `data.frame` | a structured `descr`, `shape = (nrow,)` |
| named `list` | a `.npz` |
| anything else | `zunpy_unsupported_type` |

Notes, by row:

- `logical`: `NA` is `zunpy_na_error` unless `na = "allow"`, which writes
  `False` with a warning. NumPy has no missing boolean.
- `integer`: `NA_integer_` is written as `-2147483648` only with
  `na = "allow"`.
- `double`: `NA_real_` is written bit-exact (R's NaN payload 1954), so it
  round-trips to R; NumPy sees a NaN.
- `raw`: a `raw` vector is bytes, never a string. It reads back as
  `integer`, since `|u1` is an integer dtype (a documented loss).
- `character`: n is the longest string, in code points for `U` and in
  bytes for `S`, and at least 1, as NumPy makes it; `dtype = "<U<n>"` or
  `"|S<n>"` fixes it, and a longer value is `zunpy_range_error` (§18 Q2,
  decided at Stage 4). `S` takes the UTF-8 bytes, or Latin-1 with
  `encoding = "latin1"` (a character with no Latin-1 form is
  `zunpy_range_error`), or the bytes as they are with `"bytes"`.
  `NA_character_` is an empty string with `na = "allow"`, else an error.
- `factor`: levels are lost, as in `zucbor`.
- `POSIXct`: written when its count in `unit` reads back as the same
  double, and refused (`zunpy_range_error`) when it holds a finer
  fraction; choose `unit = "ns"` or round first. "Reads back" is the rule
  of §6.1, so whatever `npy_read()` returns is written back; a microsecond
  `POSIXct`, whose double is not exactly that many microseconds, still
  writes as `M8[us]` (*settled at Stage 4*: "no fraction finer than the
  unit" alone would refuse most times). `Date` and `difftime` take whole
  units the same way; a `Date` stored as integer is days too. `NA` is
  NaT.
- `difftime`: `m8` in its own units (`secs` `s`, `mins` `m`, `hours` `h`,
  `days` `D`, `weeks` `W`), or with `dtype` in `s`, `ms`, `us` or `ns`
  from its value in seconds.
- matrix, array: `dimnames` are dropped (a documented loss).
- `data.frame`: columns by §7.3.
- named `list`: each element by this table; `npy_encode()` refuses it.
- Anything else: `NULL`, an unnamed `list`, functions, environments and
  S4 objects.

`dtype =` overrides the default for one call: `npy_write(x, f, dtype =
"<f4")` narrows doubles to single precision with round-to-nearest-even
(zubin's writer), and `dtype = "<i2"` refuses any value outside the range
with the index of the first offender. A `dtype` the R type cannot
sensibly reach (`character` to `<f8`) is `zunpy_invalid_argument`.

### 7.2 Whole doubles stay doubles

Unlike `zucbor`, zunpy does not turn a whole double into an integer. The
dtype of an R `double` is `<f8` whatever its values, because the reader
on the other side will index into a typed array and a changing dtype
would be a changing API. `1L` and `1` therefore write differently
(`<i4` against `<f8`), which is the NumPy user's expectation.

### 7.3 Data frames

Each column is one field of a structured dtype, named by the column name,
with the type the column would have as a vector. `character` columns
become `U<n>` with n the longest value in the column; list columns are
`zunpy_unsupported_type`. Row names are dropped. The data block is one
`bin_pack()` call. Field names must be valid for NumPy: non-empty, unique,
and UTF-8 (version 3.0 header if any is non-Latin-1, §9.2).

### 7.4 Known lossy conversions

| Construct | Behaviour |
| --- | --- |
| `dimnames`, `names` on a vector | dropped |
| `factor` | labels as `U<n>` |
| `NA` in `logical` or `integer` | refused, or `False` / `INT_MIN` on request |
| `NA_real_` | bit-exact NaN: `NA` in R, NaN in NumPy |
| `raw` | written `\|u1`, read back as `integer` |
| `POSIXct` `tzone` | written as UTC instants, read back as UTC |
| `U<n>` padding | trailing NULs stripped on read |
| `S<n>` with `encoding` | transcoded to UTF-8 on read |
| C-order file, `order = "R"` | permuted into R order |
| structured array, k > 1 dims | data frame plus `npy_shape` |
| `M8[ns]` beyond 2^53 ns | precision lost in a double |

Which of these round-trip: `NA_real_` does in R; the C-order permutation
does when written back with `order = "C"`; the structured array does
while `npy_shape` is present; `S<n>` does when the encoding is right;
`M8[ns]` does with `datetime = "integer64"`. The rest do not, and a
string that ends in U+0000 is cut by the NUL stripping.

What does round-trip is stated as a property and tested as one (§15):
for every `.npy` NumPy writes from the dtype table with `fortran_order`
either way, `npy_encode(npy_read(f), order = <the file's>)` is
byte-identical to `f` after header normalisation (§8), and for every R
value in the table, `npy_read(npy_write(x))` is `identical()` to `x`
except where a row above applies.

## 8. Deterministic writing

Identical R objects give identical bytes on every platform:

- **Version 1.0** unless the header would exceed 65,535 bytes, then 2.0;
  3.0 only when a structured field name is not Latin-1. This is NumPy's
  own rule, so NumPy's writer and zunpy's agree on every array that both
  can write.
- **The header dict is written exactly as NumPy writes it:**
  `{'descr': '<f8', 'fortran_order': True, 'shape': (3, 4), }` with that
  key order, single quotes, `True` and `False`, a trailing comma and
  space, and the one-element tuple form `(n,)`. Then spaces to a 64-byte
  boundary of the whole prefix (magic, version, length field, dict,
  newline), as NumPy has done since 1.14 (earlier writers used 16, which
  the reader also accepts).
- **Little-endian always**, `<` in every multi-byte `descr`, written
  through `zb_wr_*le`. A big-endian host writes the same bytes.
- **`fortran_order`** is `True` for an R array with `dim` of length 2 or
  more and `order = "F"`, since that is R's memory layout and needs no
  copy; `False` for vectors and 0-d arrays, as NumPy writes them. An
  array that is both C- and Fortran-contiguous (empty, or with at most
  one dimension above 1) is written with `False`, which is NumPy's own
  rule and gives the same bytes either way (*settled at Stage 3*).
- **The spare spaces.** NumPy pads the dict with
  `21 - len(repr(shape[growth axis]))` spaces after it (the first axis, or
  the last in Fortran order), so that an appending writer can rewrite the
  shape in place, and then pads the whole prefix to 64 bytes with 1 to 64
  further spaces (64 when it is already aligned). zunpy does both, which
  is why its output matches NumPy's byte for byte (*verified 2026-10-08*:
  every little-endian fixture but the 0-d one re-encodes identically).
  `order = "C"` permutes on write for a reader that must have C order
  (some C and Rust loaders refuse Fortran order; NumPy itself does not
  care).
- **`.npz` members** are written in the order of the list, as
  `<name>.npy`, with ZIP timestamps fixed at 1980-01-01 00:00:00 and no
  extra fields, so two writes of the same list are byte-identical. Stored
  (method 0) unless `compress = TRUE`, which is DEFLATE level 6 through
  `zukomp`, matching `numpy.savez_compressed`'s default.

## 9. The `.npy` format, as zunpy reads it

### 9.1 Prefix

| Offset | Bytes | Content |
| --- | --- | --- |
| 0 | 6 | magic `\x93NUMPY` |
| 6 | 1 | major version: 1, 2 or 3 |
| 7 | 1 | minor version: 0 |
| 8 | 2 or 4 | header length, little-endian unsigned |
| 10 or 12 | header length | the dict, space-padded, ending in a newline |

The length field is 2 bytes in version 1 and 4 bytes in versions 2 and
3, so the data begins at `10 + len` or `12 + len`. zunpy checks that this
offset is a multiple of 16 and warns, not errors, when it is not a
multiple of 64: NumPy's reader accepts any length, and files from other
writers exist.

The dict is Latin-1 in versions 1 and 2 and UTF-8 in 3; zunpy decodes it
accordingly before parsing, and refuses a byte sequence invalid in that
encoding.

### 9.2 The header grammar

A Python literal, restricted to what NumPy's writer emits and its reader
accepts through `ast.literal_eval`:

```text
header   := dict ws
value    := string | bool | none | int | tuple | list | dict
            | "(" ws value ws ")"
string   := "'" chars "'" | '"' chars '"'
            with \' \" \\ \n \t \r \xHH \uHHHH \UHHHHHHHH escapes
bool     := "True" | "False"
none     := "None"
int      := [ "-" ] ( "0" | nonzero { digit } )
tuple    := "(" ws ")" | "(" ws value ws "," ws ")"
          | "(" ws value { ws "," ws value } [ ws "," ] ws ")"   (two or more)
list     := "[" ws [ value { ws "," ws value } [ ws "," ] ] ws "]"
dict     := "{" ws [ pair { ws "," ws pair } [ ws "," ] ] ws "}"
pair     := value ws ":" ws value
ws       := { " " | "\t" | "\n" | "\r" }
```

*Settled at Stage 1.* The header must start with `{` and may end in any
whitespace; NumPy's spaces and final newline are whitespace, so the
newline is not required. `(x)` is `x` in parentheses, as in Python, so a
shape of `(3)` is an int and refused; a one-element tuple needs its comma.
An int with a leading zero is refused, as Python refuses it. A string may
not hold NUL, written or escaped, because R's strings cannot; a surrogate
code point is refused too. In versions 1 and 2 each byte of a string is
its Latin-1 code point; in version 3 the whole header must be valid UTF-8.
`None` exists for the `titles` of the dict form.

Required: `descr` (a string, or a list of field tuples, or the dict form
with `names`, `formats`, `offsets`, `itemsize`), `fortran_order` (a bool),
`shape` (a tuple of non-negative ints). Any other key, a missing key, a
duplicate key, a key that is not a string or a wrong type is
`zunpy_parse_error` with the byte offset. The grammar is a recursive
descent with an explicit depth cap of 8, which is more than any `descr`
needs and makes the parser's stack use fixed.

Field tuples: `(name, descr)` or `(name, descr, shape)`, where `name` is a
string or a `(title, name)` pair, `descr` is a string or a nested list
(refused in 0.1.0), and `shape` is a tuple of ints or one int. A subarray
field has at most 8 dimensions; more is `zunpy_unsupported_type`.
`('', '|V<n>')` is padding: NumPy writes it for aligned and offset dtypes
(*verified 2026-10-08* against NumPy 2.3.3, which writes the list form
with padding entries and never the dict form). Any other field with an
empty name is named `f<i>`, its 0-based position in the list, as NumPy
names it. Field names must be unique (`zunpy_invalid_error`).

The dict form takes `names` and `formats` (required), `offsets`,
`itemsize`, `titles` (strings or `None`) and `aligned` (a bool, ignored).
Without `offsets` the fields are packed; without `itemsize` the record
ends at its furthest field. A field that overlaps another or runs past the
itemsize is `zunpy_invalid_error`.

### 9.3 The `descr` string grammar

```text
descr    := [ order ] kind [ width ] [ "[" unit "]" ]
order    := "<" | ">" | "|" | "="
kind     := "b" | "i" | "u" | "f" | "c" | "S" | "a" | "U" | "V"
          | "M" | "m" | "O" | "g"
width    := digit { digit }
unit     := "Y" | "M" | "W" | "D" | "h" | "m" | "s"
          | "ms" | "us" | "ns" | "ps" | "fs" | "as"
```

`a` is an alias of `S`. The width is bytes for every kind but `U`, where
it is code points (4 bytes each). Allowed widths: `b1`; `i1 i2 i4 i8`;
`u1 u2 u4 u8`; `f2 f4 f8`; `c8 c16`; `S`, `a`, `U` and `V` any width from
0; `M8` and `m8` only. Anything else is `zunpy_parse_error`. `S0`, `U0`
and `V0` are legal (NumPy writes them for empty strings) and read as
empty values. A `|` order on a multi-byte kind, or `<` and `>` on a
one-byte kind, is refused: NumPy never writes it and it is the first
thing a fuzzer finds.

*Settled at Stage 1.* A missing byte order is read as `=`: little-endian
for a multi-byte kind, with the warning of §18 Q1, and `|` for a
one-byte kind. `O` (any width), `g`, `G`, `f12`, `f16`, `c24` and `c32`
are `zunpy_unsupported_type`; every other unknown kind or width is
`zunpy_parse_error`. `M8` and `m8` need a unit and take no multiplier
(`M8[10s]` is refused).

## 10. `.npz`

A `.npz` is a ZIP archive with no nesting: every member is a `.npy` file,
named `<key>.npy`, where `numpy.savez` names positional arguments
`arr_0`, `arr_1`, and so on. zunpy reads the ZIP container itself, since
the container is three fixed records that `bin_layout()` describes in
full:

```r
local_hdr <- bin_layout(
  "<sig:u32 ver:u16 flags:u16 method:u16 time:u16 date:u16 crc:u32
   csize:u32 usize:u32 nlen:u16 xlen:u16")
central_hdr <- bin_layout(
  "<sig:u32 vmade:u16 vneed:u16 flags:u16 method:u16 time:u16 date:u16
   crc:u32 csize:u32 usize:u32 nlen:u16 xlen:u16 clen:u16 disk:u16
   iattr:u16 eattr:u32 offset:u32")
eocd <- bin_layout(
  "<sig:u32 disk:u16 cdisk:u16 n:u16 total:u16 csize:u32 coffset:u32
   clen:u16")
```

Reading walks the central directory, as every correct ZIP reader does,
never the local headers alone; ZIP64 (`csize` or `usize` of
`0xFFFFFFFF`) is read from the ZIP64 extra field, since NumPy writes ZIP64
whenever a member exceeds 2 GiB. Members are located by name, so
`npy_read(f, names = "x")` touches only that member's bytes, and
`npy_names()` reads only the directory.

Each member is then decoded as a `.npy` after inflation. Method 0
(stored) needs nothing. Method 8 (DEFLATE) is a raw DEFLATE stream (RFC
1951), which zukomp 0.1.0 already provides as the codec `"deflate-raw"`
(*verified 2026-10-08*): zunpy calls `komp_decompress(x, codec =
"deflate-raw", max_output = usize)` so a zip bomb stops at the member's
declared size, and `komp_compress(x, codec = "deflate-raw", level = 6L)`
to write (D5). `zukomp` is in `Imports` for those two calls.

**Why not zukomp's ZIP reader.** zukomp installs a miniz ZIP reader in
`libzukomp.a` for C consumers such as zuxlsx (*verified 2026-10-08*). zunpy
does not use it: it is a reader only, so writing would still need the
code below; it reads from a path, not from the bounded raw vector §12
requires; and linking it costs a `configure` step. The three records
above are a few hundred lines of R and C against `bin_layout()`, and are
checked by the same limits as everything else. CRC-32 of each member is verified after inflation, with the
table written out in zunpy's C: `zufast` lists CRC32C, a different
polynomial, as deferred, and ZIP's CRC-32 is 60 lines and not worth a
cross-package request.

Writing produces the same three records, ZIP64 when a member needs it,
with the determinism rules of §8.

**Limits.** `max_size` applies to the sum of declared uncompressed sizes
before any member is inflated, so the directory alone decides whether the
file is too big. `max_members` (default 10,000) bounds the directory walk.

## 11. Errors

Every condition inherits `zunpy_error`, raised in R from a status the C
layer returns by enumerator name (the `zucbor` and `zubin` rule: C never
raises below the outermost `.Call`, and tests assert on class, never
message text).

| Class | When |
| --- | --- |
| `zunpy_invalid_argument` | an argument is unusable |
| `zunpy_parse_error` | not a `.npy`: magic, version, grammar, truncation |
| `zunpy_invalid_error` | well-formed but inconsistent |
| `zunpy_unsupported_type` | a dtype or an R value with no counterpart |
| `zunpy_unrepresentable` | a value R cannot hold |
| `zunpy_na_error` | an `NA` with no representation in the target |
| `zunpy_range_error` | a value does not fit the requested dtype |
| `zunpy_limit_error` | a limit of §12 was reached |
| `zunpy_io_error` | the file or connection could not be read or written |

Fields and detail:

- `zunpy_invalid_argument` carries `arg`; it includes a `dtype` the value
  cannot reach.
- `zunpy_parse_error` and `zunpy_invalid_error` carry `offset`, the
  0-based byte offset in the input. Too few bytes for the declared shape
  and bytes after it are both `zunpy_parse_error`, as §12 says (truncated
  or trailing data, not an inconsistency). Inconsistent means: record
  fields overlap, run past the itemsize or share a name, a `U` string
  holds a surrogate, or a CRC mismatches.
- `zunpy_unsupported_type` carries `dtype`: object, long double, nested
  structured dtypes, pickled members.
- `zunpy_unrepresentable` carries `offset` and `index`: a dimension above
  `2^31 - 1`, a string longer than R allows, an `i8` beyond 2^53 with
  `int64 = "double"`.
- `zunpy_na_error` and `zunpy_range_error` carry `index`.
- `zunpy_limit_error` carries `limit` and `limit_value`, with the
  subclasses `zunpy_size_limit`, `zunpy_header_limit`, `zunpy_dims_limit`
  and `zunpy_members_limit`.
- In a `.npz`, offsets count from the start of the member and `member`
  carries its name.

`zubin`'s own conditions from `bin_unpack()` and `bin_pack()` are
re-raised under the matching zunpy class with the same fields, so a
caller never sees a `zubin_error` from zunpy.

## 12. Limits and hostile input

Threat model: a `.npy` or `.npz` from a network, a dataset mirror or a
user upload. The header is a Python literal and NumPy's own history shows
why it is checked whole first: NumPy caps the header at 10,000 bytes by
default, since a crafted header could stall `ast.literal_eval`.

| Limit | Default | Where |
| --- | --- | --- |
| `max_size` | 2 GiB | before the prefix, from declared sizes |
| `max_header` | 10,000 bytes | the length field, before the dict is read |
| `max_dims` | 32 | the shape tuple; NumPy's own ceiling |
| `max_fields` | 1,024 | structured dtypes: the R columns, a subarray counting one per element |
| `max_members` | 10,000 | the `.npz` central directory |

When reading a connection, `max_size` is enforced while reading, at
`max_size + 1` bytes, as `cbor_read()` does.

**Shape times itemsize is computed saturating** in `uint64_t` and compared
with the bytes actually present before any allocation; a header claiming
`(2**40, 2**40)` costs nothing. A declared size that fits the limit but
exceeds the bytes present is `zunpy_parse_error` (truncation); bytes
beyond the declared size are `zunpy_parse_error` too, since NumPy's own
reader rejects trailing data.

**No element is larger than `max_size`** (*settled at Stage 2*, found by
the fuzzer in CI): with a zero dimension nothing else bounds the itemsize,
and a subarray shape such as `(3, 6666666666666666666)` saturates it, yet
the build phase sizes buffers by it. **The columns a record makes are
bounded by `max_fields`**, a subarray counting one per element, so that a
subarray of zero-width elements cannot ask for a billion columns.

**Zero-width types are bounded too** (*settled at Stage 1*). `S0`, `V0`
and an empty record declare elements with no bytes behind them, so the
byte comparison cannot bound them, yet the build phase makes one R value
per element. For a zero itemsize the element count must not exceed
`max_size`.

**Nothing is allocated from a header field.** The plan the check phase
hands to the build phase carries sizes the check phase has verified
against the input length, and the build phase allocates from the plan
only, as `zucbor` does with container counts.

**Interrupts.** The conversion loops call `R_CheckUserInterrupt()` every
2^20 elements; everything they hold is `PROTECT`ed or in the `zubin`
builder, so an interrupt leaks nothing.

**No evaluation, ever.** The header parser is a grammar, not an
evaluator: it has no identifiers, no arithmetic and no calls, so a header
that is a valid Python expression but not in §9.2 is a parse error.

## 13. Memory model

- Reading a path uses `readBin()` in 64 KiB blocks bounded by `max_size`,
  as `cbor_read()` does; the whole file is in one raw vector before the
  check phase runs. Lazy reading comes in zunpy 0.2.0, on zubin 0.3.0
  views and zubin 0.4.0 memory maps (*verified 2026-10-08*).
- The check phase allocates nothing itself. It runs in two calls: the
  first reads the prefix and bounds the header length by `max_header`
  and by the bytes present, and returns the scratch size; the caller
  `R_alloc()`s it (the fuzzer `malloc()`s it) and the second call parses
  into it. The scratch holds at most one 32-byte node per header byte,
  the field table (at most `max_fields` entries) and the decoded strings:
  about 550 KB at the default limits, and linear in `max_header`.
- The build phase allocates the result once, from the plan, and converts
  in place. A C-order permutation needs one temporary of the same size.
- The writer's output is one raw vector, allocated at its final size
  before anything is written (§4); a C-order write packs into an
  `R_alloc()`ed temporary and permutes into it.
- Strings go through `mkCharLenCE()` once per element; a `U<n>` column
  of one million elements is one million `CHARSXP`s, which is R's cost,
  not zunpy's, and the documentation says so.

## 14. Build, portability and CRAN

- C99, `-Wall -Wextra -Wpedantic -Wshadow -Wstrict-prototypes` clean
  under `-std=gnu17` (the family's lint gate); every typed access goes
  through `zubin` and `zufast`'s `memcpy` helpers, so alignment and byte
  order never matter.
- `DESCRIPTION`: `LinkingTo: zubin (>= 0.1.0), zufast (>= 0.1.0)`,
  `Imports: zukomp (>= 0.1.0)`, `Suggests: bit64, testthat, withr, knitr,
  rmarkdown`. None of the three is on CRAN and zubin is at
  `0.0.0.9000` (*verified 2026-10-08*), so development carries `Remotes:
  pedrobtz/zubin@main, pedrobtz/zufast@main, pedrobtz/zukomp@main`. No
  `Remotes:` in a submitted tarball (R10.2); the package is rebuilt
  against the CRAN tarballs of all three before each submission (R10.3).
- `src/Makevars`: `PKG_CFLAGS = $(C_VISIBILITY)`, object files listed by
  hand, portable make only.
- The shared object exports `R_init_zunpy` only, audited by the `abi`
  test copied from `zubin`.
- CRAN order: `zufast`, then `zubin`, and `zukomp`, then zunpy. Nothing
  else waits (R10.5). zunpy cannot be submitted before all three are
  accepted, and is the first package to consume both header-only
  providers, so it is also the proof of that shape under CRAN's
  reverse-dependency checks.
- Workflows from `pedrobtz/r-actions` with the family's standard set
  (R5): `R-CMD-check`, `coverage`, `pkgdown`, `native-checks` (ASan,
  UBSan, valgrind, rchk, gctorture), `hardening` (lint, fuzz).

## 15. Testing

- **Fixtures from NumPy, never by hand.** `tools/make-fixtures.py` writes
  one `.npy` per dtype row of §6.1, each in both orders and both byte
  orders where applicable, plus the `.npz` cases, with NumPy pinned in the
  script's header. The files are committed under
  `tests/testthat/fixtures/npy/` with a `MANIFEST.tsv` row each: dtype,
  shape, order, NumPy version, SHA-256, and every value in C order
  (floats as `float.hex()`, which R's `as.numeric()` reads exactly; its
  decimal reading of `1.7976931348623157e+308` is `Inf`).
  `tools/check-fixtures` regenerates and diffs them in CI's
  `conformance` job, with NumPy through `uv`.
- **The oracle is NumPy, by way of the MANIFEST** (*settled at Stage 2*,
  replacing `reticulate`). In the `conformance` job,
  `tools/conformance.py` checks that every MANIFEST row is what
  `np.load()` reads from its file; on every platform, the R suite checks
  that `npy_decode()` reads the same values from the same file. Together
  they compare zunpy with NumPy without R and Python in one process, and
  `R CMD check` needs no Python. From Stage 3, R writes files for
  `np.load()` to read in the same job. `reticulate` is not used.
- **Round trip as a property** (§7.4): 300 generated arrays over every
  dtype, shape of 0 to 4 dimensions including zero-length dimensions, both
  orders, with `NA`, `NaN`, `-0`, infinities, the empty string and a
  string ending in `U+0000`; each encoded twice (identical bytes) and
  decoded back (`identical()`, modulo the documented losses).
- **The header parser is fuzzed** with libFuzzer under ASan and UBSan,
  seeded from every fixture header and NumPy's own test-suite headers;
  the canary must crash first. Every proper prefix of every fixture is a
  truncation (`zunpy_parse_error`), never a crash and never a value.
- **Hostile headers**, each a permanent regression: `shape` of
  `(2**40, 2**40)`; 33 dimensions; a 10,001-byte header; a header with a
  nested list 9 deep; `descr` of `'<i3'`, `'|f8'`, `'<b1'`, `'<U'`,
  `'<M8[x]'`; a duplicate key; a key that is not a string; an `O` dtype;
  a `.npz` whose directory declares 2^32 members; a member whose `usize`
  is 2 GiB with a 100-byte stream; a CRC mismatch.
- **The mutation check** (`tools/run-mutation-check`, from `zucbor`): each
  `/* GUARD: name */` in the check phase is disabled in turn and the
  matching hostile input must then pass, proving the guard is load-bearing.
- **Big-endian** reads are tested by fixtures written with `>`. Until the
  `memcpy` fast path of Stage 7 exists, no code depends on the host's
  byte order, so `-DZNP_FORCE_BE_HOST` arrives with that path.
- Tests are self-sufficient, pass under `shuffle = TRUE`, stay serial, and
  the CRAN suite runs in under 15 s; the 2 GiB and 10^6-member cases call
  `skip_heavy()` and run only in the nightly job.

## 16. Performance targets

Against `RcppCNPy` and `reticulate` on 10^7 doubles (80 MB) and 10^7
`i4`, measured by `tools/run-benchmarks` and recorded in the design:

- Reading a little-endian `f8` or `i4` Fortran-order file is one `memcpy`
  plus the header: within 10% of `readBin()` on the same bytes.
- A C-order matrix costs one extra pass (the permutation).
- Writing is one pass into the builder: within 10% of `writeBin()`.
- `U<n>` strings are bounded by `mkCharLenCE()`; the target is to be no
  slower than `readBin()` plus `iconv()` on the same bytes.
- `.npz` stored members add the directory walk only; deflated members are
  `zukomp`'s speed.

## 17. Decisions

| # | Question | Decision |
| --- | --- | --- |
| D1 | Dependencies | `LinkingTo: zubin, zufast`; `Imports: zukomp` |
| D2 | `.npz` API | `npy_read()` and `npy_write()` detect and dispatch |
| D3 | Whole doubles | stay `<f8` (§7.2), unlike `zucbor` |
| D4 | Memory order on read | `order = "R"` permutes; `"file"` keeps bytes |
| D5 | DEFLATE | zukomp's existing codec `"deflate-raw"`, RFC 1951 |
| D6 | CRC-32 | zunpy's own 60 lines; not a `zufast` request |
| D7 | `datetime64` | `POSIXct` in UTC, `Date` at `D`, else `integer64` |
| D8 | Header padding on read | any length; below 64 warns, below 16 errors |
| D9 | `fortran_order` on write | `True` for arrays, `False` for vectors and for arrays NumPy would call both orders |
| D10 | Info function | `zunpy_info()`, the package name (R1) |
| D11 | Structured arrays, k > 1 dims | a data frame carrying `npy_shape` |
| D12 | Header evaluation | a grammar with a depth cap, never an evaluator |
| D13 | C-order permutation | in C, one pass; never `aperm()` in R |
| D14 | Lazy reads | not in 0.1.0; on `zubin` views in 0.2.0 (§2, §13) |

Reasons where they are not in the section cited:

- D1: zunpy writes no byte-level code of its own, so the gain from the
  providers is the whole package, not "one fewer buffer", which is R10.1's
  test for a dependency.
- D2: one R prefix per package; a named list is a `.npz`; `npz_*`
  aliases only if asked.
- D5: the RFC planned a zukomp issue for a raw codec; zukomp 0.1.0
  already has it as `"deflate-raw"` (*verified 2026-10-08*), so there is
  no request and no fallback. zukomp's ZIP reader is not used (§10).
- D7: `POSIXct` is written as `<M8[us]`; `unit =` chooses.
- D9: `order = "C"` permutes on write for readers that need it.

## 18. Open questions

1. **`=` byte order.** NumPy never writes it; some writers do. Accept as
   little-endian with a warning, or refuse? Recommended: accept with a
   warning, since the alternative is a file nobody can read.
2. *Decided at Stage 4:* the override is `dtype = "<U<n>"` (or `"|S<n>"`),
   with the default as stated; §7.1 says how.
3. **`.npz` member names.** NumPy allows any string; ZIP names are bytes.
   Refuse names with `/`, `\`, NUL or a leading `..`? Recommended: yes,
   since a reader elsewhere may extract to disk.
4. **The 10,000-byte header default** is NumPy's; a structured dtype with
   1,024 fields can exceed it. Raise `max_header` or lower `max_fields`?
   Recommended: keep both defaults and document that one bounds the other.
5. **Version 3.0 headers** are rare (non-Latin-1 field names). Read
   support is cheap; write support means tracking NumPy's own rule.
   Recommended: both, since the rule is one line.

## 19. Roadmap

The stages, their exit criteria and their status are in
[roadmap.md](roadmap.md). This section keeps its number so that the
references to §19 and §20 elsewhere stay valid.

## 20. Acceptance criteria for v0.1.0

1. Builds from source on Windows, macOS and Linux, R release, devel and
   oldrel, with `zubin`, `zufast` and `zukomp` from CRAN and nothing
   else installed at run time.
2. No R object is allocated before the check phase has passed; verified
   by the `(2**40, 2**40)` header and the `max_size` fixtures.
3. Every truncated, oversized, malformed or hostile input of §15 fails
   through a classed `zunpy_error`; none crashes, hangs or reaches the
   allocator unbounded; the fuzz gate has been seen to fail on its canary.
4. Every dtype row of §6.1 and §7.1 has a NumPy-written fixture and a
   test, and the three copies of each table (design, roxygen, tests)
   agree.
5. Writing is deterministic: byte-identical across calls, sessions and
   platforms, and byte-identical to NumPy's own output for every array
   both can write.
6. The round-trip properties of §7.4 hold over the generated corpus.
7. Big-endian files read identically on a little-endian host, and the
   forced-big-endian build passes the suite.
8. `R CMD check --as-cran` is clean on every CI platform; the shared
   object exports `R_init_zunpy` only; no stdio or exit symbols.
9. zunpy builds against the CRAN tarballs of `zubin`, `zufast` and
   `zukomp`, not `main`.
10. `RcppCNPy`'s own test files, where its licence allows them to be
    committed, read to the same values.

## 21. What this design does not decide

- Whether zunpy is worth more than a `reticulate` recipe. The case is
  §3's gap: no Python, every dtype, and the limits. If the maintainer
  judges the audience too small, the design still serves as the worked
  example of a `zubin` consumer that the family's R10.4 asks for.

Review prepared with assistance from generative AI.
