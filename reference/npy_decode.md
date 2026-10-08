# Read a NumPy array from bytes

Decodes a `.npy` file already in memory into an R vector, matrix or
array. The header is parsed and checked whole, and the declared shape
compared with the bytes present, before anything is allocated.

## Usage

``` r
npy_decode(
  x,
  order = c("R", "file"),
  int64 = c("double", "integer64"),
  na = c("error", "allow"),
  strings = c("character", "raw"),
  encoding = c("UTF-8", "latin1", "bytes"),
  datetime = c("convert", "integer64"),
  max_size = 2 * 1024^3,
  max_header = 10000,
  max_dims = 32
)
```

## Arguments

- x:

  A raw vector holding a whole `.npy` file.

- order:

  `"R"` to index as NumPy does, or `"file"` to keep the file's memory
  order.

- int64:

  `"double"` or `"integer64"` (needs the bit64 package to be useful) for
  `i8` and `u8`.

- na:

  `"error"` or `"allow"`: whether a value that is `NA` in R is refused.

- strings:

  `"character"` or `"raw"`, for `S<n>`.

- encoding:

  The encoding of `S<n>` bytes: `"UTF-8"` (validated), `"latin1"`
  (converted to UTF-8) or `"bytes"` (left as bytes).

- datetime:

  `"convert"` to `Date`, `POSIXct` and `difftime`, or `"integer64"` for
  the counts as they are.

- max_size:

  The largest input accepted, in bytes.

- max_header:

  The largest header accepted, in bytes; NumPy's own default.

- max_dims:

  The most dimensions accepted, at most 64.

## Value

A vector, matrix or array.

## Details

Types map as follows: `b1` to logical; `i1`, `u1`, `i2`, `u2` and `i4`
to integer; `u4`, `f2`, `f4` and `f8` to double; `i8` and `u8` to
double, or to `integer64` with `int64 = "integer64"`; `c8` and `c16` to
complex. Every value is converted exactly or refused: an `i4` of `-2^31`
is R's `NA_integer_`, so it is an error unless `na = "allow"`, and a
64-bit integer beyond `2^53` in magnitude, which a double cannot hold
exactly, is an error unless `int64 = "integer64"`. Structured dtypes are
not supported yet.

Strings: `S<n>` (bytes) and `U<n>` (code points) become character
vectors in UTF-8, with the trailing NULs NumPy pads with removed. `S<n>`
bytes are decoded as `encoding` says, and `strings = "raw"` returns each
as a raw vector instead. A NUL inside a value cannot live in an R string
and is an error. `V<n>` becomes a list of raw vectors.

Dates and times: `M8[D]` becomes `Date`; `M8[s]`, `M8[ms]`, `M8[us]` and
`M8[ns]` become `POSIXct` in UTC; `m8` becomes `difftime` in days,
hours, minutes, weeks or seconds (`ms`, `us` and `ns` scaled to
seconds). NaT is `NA`. A double cannot hold every nanosecond since 1970,
so `M8[ns]` is the nearest double; `datetime = "integer64"` keeps the
counts exactly. Units with no R class (`Y`, `M` and finer than `ns`) are
returned as `integer64` counts either way. Such an `integer64` carries
the dtype in its `npy_dtype` attribute, and
[`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md)
writes it back as that dtype.

A 0-d array becomes a length-1 vector and a 1-d array a vector, both
without `dim`. NumPy's default C order (last index fastest) is permuted
into R's column-major order, so that `a[i, j]` in R is `a[i-1, j-1]` in
Python; `order = "file"` skips the permutation and returns the array
with its dimensions reversed, its memory identical to the file's.

## See also

[`npy_header()`](https://pedrobtz.github.io/zunpy/reference/npy_header.md)
for the header alone;
[zunpy-conditions](https://pedrobtz.github.io/zunpy/reference/zunpy-conditions.md)
for the errors.

## Examples

``` r
# A 2 x 3 little-endian double matrix in C order, as numpy.save() writes it.
dict <- "{'descr': '<f8', 'fortran_order': False, 'shape': (2, 3), }"
pad <- (64 - (10 + nchar(dict) + 1) %% 64) %% 64
header <- c(charToRaw(dict), rep(charToRaw(" "), pad), charToRaw("\n"))
x <- c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0)),
       as.raw(c(length(header), 0)), header,
       writeBin(as.double(0:5), raw(), size = 8, endian = "little"))
npy_decode(x)
#>      [,1] [,2] [,3]
#> [1,]    0    1    2
#> [2,]    3    4    5
```
