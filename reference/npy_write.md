# Write a NumPy file

Encodes `x` as
[`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md)
does and writes it to a path or a connection: an array, a data frame or
another value as a `.npy`, a named list as a `.npz`.

## Usage

``` r
npy_write(x, file, ...)
```

## Arguments

- x:

  The value to write; see
  [`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md).

- file:

  A path or a connection.

- ...:

  Further arguments of
  [`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md):
  `dtype`, `order`, `na`, `encoding`, `unit` and `compress`.

## Value

`file`, invisibly.

## Details

A path is overwritten. A connection that is not open is opened in binary
mode and closed again; an open one must be binary and is left open.

## See also

[`npy_read()`](https://pedrobtz.github.io/zunpy/reference/npy_read.md).

## Examples

``` r
f <- tempfile(fileext = ".npz")
npy_write(list(a = 1:3, b = c("x", "y")), f, compress = TRUE)
npy_names(f)
#> [1] "a" "b"
str(npy_read(f))
#> List of 2
#>  $ a: int [1:3] 1 2 3
#>  $ b: chr [1:2] "x" "y"
unlink(f)
```
