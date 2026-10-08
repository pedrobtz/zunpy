# The NumPy dtype for an R value

The dtype string
[`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md)
writes for `x` when no `dtype` is given.

## Usage

``` r
npy_dtype(x)
```

## Arguments

- x:

  An R value.

## Value

A string such as `"<f8"`.

## Examples

``` r
npy_dtype(1:3)
#> [1] "<i4"
npy_dtype(c(TRUE, FALSE))
#> [1] "|b1"
npy_dtype(matrix(0, 2, 2))
#> [1] "<f8"
```
