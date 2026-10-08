# Write an R array as NumPy bytes

Encodes an R vector, matrix or array as a `.npy` file in a raw vector.
The bytes are deterministic, and identical to what `numpy.save()` writes
for the same array.

## Usage

``` r
npy_encode(
  x,
  dtype = NULL,
  order = c("F", "C"),
  na = c("error", "allow"),
  encoding = c("UTF-8", "latin1", "bytes"),
  unit = c("us", "ns", "ms", "s"),
  compress = FALSE
)
```

## Arguments

- x:

  A logical, integer, double, complex, raw or character vector, matrix
  or array, a factor, a `Date`, `POSIXct` or `difftime` vector, a
  [`bit64::integer64`](https://bit64.r-lib.org/reference/bit64-package.html)
  vector, a data frame of such columns, or a named list of any of these.

- dtype:

  `NULL` for the default of the R type; for a data frame, a named
  character vector of dtypes for some of its columns; else a NumPy dtype
  string: `"|b1"`, `"|i1"`, `"<i2"`, `"<i4"`, `"<i8"`, `"|u1"`, `"<u2"`,
  `"<u4"`, `"<u8"`, `"<f2"`, `"<f4"`, `"<f8"`, `"<c8"`, `"<c16"`,
  `"<U<n>"`, `"|S<n>"`, `"<M8[<unit>]"` or `"<m8[<unit>]"`.

- order:

  `"F"` (R's order) or `"C"` (NumPy's default).

- na:

  `"error"` or `"allow"`; see Details.

- encoding:

  For `|S<n>` output: `"UTF-8"` writes each string's UTF-8 bytes,
  `"latin1"` converts to Latin-1 first (a character with no Latin-1 form
  is an error), and `"bytes"` writes the bytes as they are.

- unit:

  The unit for `POSIXct`: `"us"` (the default), `"ns"`, `"ms"` or `"s"`.

- compress:

  For a list (a `.npz`), whether to compress the members.

## Value

A raw vector holding a whole `.npy` file, or a `.npz` file for a list.

## Details

By default the dtype follows the R type (see
[`npy_dtype()`](https://pedrobtz.github.io/zunpy/reference/npy_dtype.md)):
logical to `|b1`, integer to `<i4`, double to `<f8` (whole numbers too),
complex to `<c16`, raw to `|u1`, `integer64` to `<i8`, character and
factor (its labels) to `<U<n>` with `n` the most code points of any
value, `Date` to `<M8[D]`, `POSIXct` to `<M8[us]` (see `unit`) and
`difftime` to `m8` in its units (`s`, `m`, `h`, `D` or `W`). An
`integer64` that
[`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
returned for a datetime unit without an R class is written back as its
`npy_dtype`.

`dtype` chooses another dtype for one call: a numeric one for a number,
`"<U<n>"` or `"|S<n>"` (or `"<U"` and `"|S"` for the widest value) for a
string, `"<M8[s]"` and the like for a date-time. A value that does not
fit is an error naming its index, never a wrap, a truncation or a
rounding to an integer; floats round to nearest even. A date-time is
written when its count in the unit reads back as the same double, and
refused when it holds a finer fraction. Multi-byte dtypes are always
little-endian.

`NA` has no place in most NumPy types. A logical `NA` is an error unless
`na = "allow"`, which writes `False` with a warning; an integer `NA` is
an error unless `na = "allow"`, which writes `-2147483648` into `<i4`
(what R reads back as `NA`) or NaN into a float. A double `NA` is
written bit for bit into `<f8`, so R reads it back as `NA` and NumPy
sees a NaN. A character `NA` is an error unless `na = "allow"`, which
writes an empty string. A date-time `NA` is NaT.

A data frame is written as a structured array (a NumPy record array):
one field per column, named as the column and typed as the column would
be on its own, packed in column order, one record per row. `dtype` may
then be a named character vector giving the dtype of some columns. Row
names are dropped. A data frame that
[`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
made from an array of records with other than one dimension carries
`npy_shape`, and is written back with that shape. Field names must be
non-empty and unique.

A named list is written as a `.npz`: a ZIP archive holding each element
as `<name>.npy`, in list order, stored, or compressed with DEFLATE when
`compress = TRUE` (what `numpy.savez_compressed()` writes). Names must
be non-empty and unique, and may not hold a path separator or start with
`..`. The archive is deterministic: every member is dated 1980-01-01, as
NumPy dates them. `dtype` is then a list named by elements.

A matrix or array is written in R's own (Fortran) order with
`fortran_order` set, which costs no copy; `order = "C"` writes C order
for readers that need it. `dimnames` and names are dropped. A length-1
vector is a 1-d array of one element: R has no 0-d array.

## See also

[`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
to read it back.

## Examples

``` r
x <- matrix(c(1.5, 2, 3, 4), 2)
bytes <- npy_encode(x)
identical(npy_decode(bytes), x)
#> [1] TRUE
npy_header(bytes)$descr
#> [1] "<f8"
npy_header(npy_encode(1:3, dtype = "|u1"))$descr
#> [1] "|u1"
```
