# Write an R array as NumPy bytes

Encodes an R vector, matrix or array as a `.npy` file in a raw vector.
The bytes are deterministic, and identical to what `numpy.save()` writes
for the same array.

## Usage

``` r
npy_encode(x, dtype = NULL, order = c("F", "C"), na = c("error", "allow"))
```

## Arguments

- x:

  A logical, integer, double, complex or raw vector, matrix or array, or
  a
  [`bit64::integer64`](https://bit64.r-lib.org/reference/bit64-package.html)
  vector.

- dtype:

  `NULL` for the default of the R type, or a NumPy dtype string:
  `"|b1"`, `"|i1"`, `"<i2"`, `"<i4"`, `"<i8"`, `"|u1"`, `"<u2"`,
  `"<u4"`, `"<u8"`, `"<f2"`, `"<f4"`, `"<f8"`, `"<c8"` or `"<c16"`.

- order:

  `"F"` (R's order) or `"C"` (NumPy's default).

- na:

  `"error"` or `"allow"`; see Details.

## Value

A raw vector holding a whole `.npy` file.

## Details

By default the dtype follows the R type (see
[`npy_dtype()`](https://pedrobtz.github.io/zunpy/reference/npy_dtype.md)):
logical to `|b1`, integer to `<i4`, double to `<f8` (whole numbers too),
complex to `<c16`, raw to `|u1` and `integer64` to `<i8`. `dtype`
chooses another numeric dtype for one call: a value that does not fit it
is an error naming its index, never a wrap or a rounding to an integer;
floats round to nearest even. Multi-byte dtypes are always
little-endian.

`NA` has no place in most NumPy types. A logical `NA` is an error unless
`na = "allow"`, which writes `False` with a warning; an integer `NA` is
an error unless `na = "allow"`, which writes `-2147483648` into `<i4`
(what R reads back as `NA`) or NaN into a float. A double `NA` is
written bit for bit into `<f8`, so R reads it back as `NA` and NumPy
sees a NaN.

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
