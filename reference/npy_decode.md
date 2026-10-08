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
exactly, is an error unless `int64 = "integer64"`. String, date-time,
void and structured dtypes are not supported yet.

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
