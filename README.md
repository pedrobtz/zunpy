# zunpy

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zunpy/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zunpy/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zunpy/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zunpy/actions/workflows/coverage.yaml)
<!-- badges: end -->

zunpy reads and writes NumPy's array files, `.npy` and `.npz`, to and from
R vectors, matrices, arrays, data frames and lists, without Python.

- **Every dtype NumPy writes for data**: booleans, integers of every
  width, half, single and double floats, complex, `S` and `U` strings,
  `datetime64` and `timedelta64`, and structured dtypes (record arrays),
  in either byte order and either memory order. Object arrays and long
  doubles have no R counterpart and are refused.
- **Exact or refused.** A value that does not fit its target is an error
  naming its index, never a rounding or a wrap: an `int64` beyond 2^53
  needs `int64 = "integer64"`, and `NA` goes only where it has a place.
- **Safe with untrusted files.** The header is parsed by a grammar, never
  evaluated, and checked whole against the bytes present before anything
  is allocated; `.npz` archives are bounded before any member is
  inflated. Both parsers are fuzzed.
- **Byte-identical to NumPy.** What zunpy writes is what `numpy.save()`
  and `numpy.savez()` write for the same array.

## Installation

Install the released version from CRAN:

``` r
install.packages("zunpy")
```

or the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("pedrobtz/zunpy")
```

## Example

``` r
library(zunpy)

f <- tempfile(fileext = ".npy")
npy_write(matrix(c(1.5, 2, 3, 4), 2), f)
npy_read(f)
#>      [,1] [,2]
#> [1,]  1.5    3
#> [2,]  2.0    4

npy_header(f)$descr
#> [1] "<f8"

# A named list is a .npz archive; a data frame is a record array.
z <- tempfile(fileext = ".npz")
npy_write(list(x = 1:3, df = data.frame(id = 1:2, name = c("a", "b"))), z,
          compress = TRUE)
npy_names(z)
#> [1] "x"  "df"
str(npy_read(z, names = "df"))
#> List of 1
#>  $ df:'data.frame':  2 obs. of  2 variables:
#>   ..$ id  : int [1:2] 1 2
#>   ..$ name: chr [1:2] "a" "b"
```

In Python, `numpy.load()` reads both files back.

See `vignette("zunpy")` for the type mapping, memory order, archives,
limits and what does not round-trip.
